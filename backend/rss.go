package main

import (
	"bytes"
	"context"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// XML structs for parsing
type RSSFeedXML struct {
	XMLName xml.Name `xml:"rss"`
	Channel struct {
		Title string `xml:"title"`
		Items []struct {
			Title       string `xml:"title"`
			Link        string `xml:"link"`
			Description string `xml:"description"`
			PubDate     string `xml:"pubDate"`
		} `xml:"item"`
	} `xml:"channel"`
}

type AtomFeedXML struct {
	XMLName xml.Name `xml:"feed"`
	Title   string   `xml:"title"`
	Entries []struct {
		Title string `xml:"title"`
		Link  struct {
			Href string `xml:"href,attr"`
		} `xml:"link"`
		Summary string `xml:"summary"`
		Content string `xml:"content"`
		Updated string `xml:"updated"`
	} `xml:"entry"`
}

// Preset RSS feeds
var presetFeeds = []RssFeed{
	{
		Name:         "Google News World",
		URL:          "https://news.google.com/rss/topics/CAAqJggKIiBDQkFTRWdvSUwyMHZNRGx1YlY4U0FtVnVHZ0pWVXlnQVAB?hl=en-US&gl=US&ceid=US:en",
		ScheduleTime: "", // Empty: manual only by default
	},
	{
		Name:         "BBC News World",
		URL:          "https://feeds.bbci.co.uk/news/world/rss.xml",
		ScheduleTime: "", // Empty: manual only by default
	},
	{
		Name:         "NYT World News",
		URL:          "https://rss.nytimes.com/services/xml/rss/nyt/World.xml",
		ScheduleTime: "", // Empty: manual only by default
	},
	{
		Name:         "TechCrunch",
		URL:          "https://techcrunch.com/feed/",
		ScheduleTime: "", // Empty: manual only by default
	},
	{
		Name:         "Hacker News",
		URL:          "https://news.ycombinator.com/rss",
		ScheduleTime: "", // Empty: manual only by default
	},
}

// InitPresetFeeds populates preset feeds if the collection is empty
func InitPresetFeeds() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	count, err := RssFeedColl.CountDocuments(ctx, bson.M{})
	if err != nil {
		log.Printf("Failed to count RSS feeds: %v", err)
		return
	}

	if count == 0 {
		log.Println("Seeding preset international RSS feeds...")
		for _, f := range presetFeeds {
			f.ID = primitive.NewObjectID().Hex()
			f.CreatedAt = time.Now()
			_, err := RssFeedColl.InsertOne(ctx, f)
			if err != nil {
				log.Printf("Failed to insert preset feed %s: %v", f.Name, err)
			}
		}
	}
}

// ScrapeFeed fetches feed XML, parses entries, runs AI summaries, and persists to DB
func ScrapeFeed(feed RssFeed) error {
	log.Printf("Starting scrape for feed: %s (%s)", feed.Name, feed.URL)

	client := &http.Client{
		Timeout: 30 * time.Second,
	}

	req, err := http.NewRequest("GET", feed.URL, nil)
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	// Set a user agent to prevent blocks from news organizations
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("failed to fetch URL: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("bad status code: %d", resp.StatusCode)
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("failed to read response body: %w", err)
	}

	var articles []RssArticle

	// Try RSS 2.0 first
	var rss RSSFeedXML
	if errRSS := xml.Unmarshal(bodyBytes, &rss); errRSS == nil && len(rss.Channel.Items) > 0 {
		for _, item := range rss.Channel.Items {
			pubTime := parsePubDate(item.PubDate)
			articles = append(articles, RssArticle{
				FeedID:      feed.ID,
				FeedName:    feed.Name,
				Title:       cleanHTML(item.Title),
				URL:         item.Link,
				Summary:     cleanHTML(item.Description),
				PublishedAt: pubTime,
				CreatedAt:   time.Now(),
			})
		}
	} else {
		// Try Atom feed
		var atom AtomFeedXML
		if errAtom := xml.Unmarshal(bodyBytes, &atom); errAtom == nil && len(atom.Entries) > 0 {
			for _, entry := range atom.Entries {
				pubTime := parsePubDate(entry.Updated)
				summary := entry.Summary
				if summary == "" {
					summary = entry.Content
				}
				articles = append(articles, RssArticle{
					FeedID:      feed.ID,
					FeedName:    feed.Name,
					Title:       cleanHTML(entry.Title),
					URL:         entry.Link.Href,
					Summary:     cleanHTML(summary),
					PublishedAt: pubTime,
					CreatedAt:   time.Now(),
				})
			}
		} else {
			return fmt.Errorf("unable to parse response as RSS or Atom XML")
		}
	}

	log.Printf("Parsed %d articles from %s", len(articles), feed.Name)

	// Fetch the model mapped to this feed
	var targetModel *AIModel
	if feed.ModelID != "" {
		var model AIModel
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		err = ModelColl.FindOne(ctx, bson.M{"_id": feed.ModelID}).Decode(&model)
		cancel()
		if err == nil {
			targetModel = &model
		} else {
			// Fallback: search by custom_name if ID match fails
			ctx, cancel = context.WithTimeout(context.Background(), 5*time.Second)
			err = ModelColl.FindOne(ctx, bson.M{"custom_name": feed.ModelID}).Decode(&model)
			cancel()
			if err == nil {
				targetModel = &model
			}
		}
	}

	// Iterate articles and process
	newCount := 0
	for _, art := range articles {
		if art.URL == "" {
			continue
		}

		// Check if already exists in DB
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		existsCount, err := RssArticleColl.CountDocuments(ctx, bson.M{"url": art.URL})
		cancel()
		if err == nil && existsCount > 0 {
			continue // skip duplicates
		}

		// Generate AI Summary if a model is mapped
		if targetModel != nil {
			summaryText, err := generateAISummary(targetModel, art.Title, art.Summary)
			if err == nil && summaryText != "" {
				art.AISummary = summaryText
				art.ModelUsed = targetModel.CustomName
			} else {
				log.Printf("Failed to generate AI summary for article %s: %v", art.Title, err)
				art.AISummary = truncateText(art.Summary, 200)
			}
		} else {
			art.AISummary = truncateText(art.Summary, 200)
		}

		art.ID = primitive.NewObjectID().Hex()
		ctx, cancel = context.WithTimeout(context.Background(), 5*time.Second)
		_, err = RssArticleColl.InsertOne(ctx, art)
		cancel()
		if err != nil {
			log.Printf("Failed to insert article %s: %v", art.Title, err)
		} else {
			newCount++
		}
	}

	log.Printf("Successfully saved %d new articles for %s", newCount, feed.Name)

	// Update feed metadata
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, _ = RssFeedColl.UpdateOne(ctx, bson.M{"_id": feed.ID}, bson.M{
		"$set": bson.M{
			"last_scraped_at":  time.Now(),
			"last_scraped_day": time.Now().Format("2006-01-02"),
		},
	})

	return nil
}

// generateAISummary communicates with the OpenAI compatible provider to summarize the text
func generateAISummary(model *AIModel, title, content string) (string, error) {
	log.Printf("Requesting AI summary from model: %s", model.CustomName)

	promptContent := fmt.Sprintf("标题: %s\n内容: %s", title, content)
	systemMessage := "你是一个专业的多语言新闻翻译与摘要助手。请将提供的新闻内容翻译并总结为一段精炼的简体中文摘要，字数控制在150字以内，保留核心事实与观点。无论输入内容是何种语言（如英文），最终的摘要产物必须是简体中文。"

	requestBody := map[string]interface{}{
		"model": model.ProviderModel,
		"messages": []map[string]interface{}{
			{"role": "system", "content": systemMessage},
			{"role": "user", "content": promptContent},
		},
		"stream": false,
	}

	jsonBytes, err := json.Marshal(requestBody)
	if err != nil {
		return "", err
	}

	providerBase := strings.TrimSuffix(model.ProviderBaseURL, "/")
	targetURL := providerBase + "/chat/completions"
	if !strings.HasSuffix(providerBase, "/v1") && !strings.Contains(providerBase, "/chat/completions") {
		targetURL = providerBase + "/v1/chat/completions"
	} else if strings.Contains(providerBase, "/chat/completions") {
		targetURL = providerBase
	}

	req, err := http.NewRequest("POST", targetURL, bytes.NewBuffer(jsonBytes))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+model.ProviderAPIKey)

	client := &http.Client{
		Timeout: 90 * time.Second,
	}

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		respBytes, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("model provider error (status: %d): %s", resp.StatusCode, string(respBytes))
	}

	var responseMap map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&responseMap); err != nil {
		return "", err
	}

	choices, ok := responseMap["choices"].([]interface{})
	if !ok || len(choices) == 0 {
		return "", fmt.Errorf("invalid choices response from provider")
	}

	choiceMap, ok := choices[0].(map[string]interface{})
	if !ok {
		return "", fmt.Errorf("invalid choice format")
	}

	messageMap, ok := choiceMap["message"].(map[string]interface{})
	if !ok {
		return "", fmt.Errorf("invalid message format")
	}

	contentStr, ok := messageMap["content"].(string)
	if !ok {
		return "", fmt.Errorf("content is not a string")
	}

	return strings.TrimSpace(contentStr), nil
}

// StartRssScheduler starts the background ticker loop
func StartRssScheduler() {
	log.Println("Starting background RSS Scraper Scheduler...")
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		now := time.Now()
		currentTime := now.Format("15:04")
		currentDay := now.Format("2006-01-02")

		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		cursor, err := RssFeedColl.Find(ctx, bson.M{
			"schedule_time":    bson.M{"$ne": ""},
			"last_scraped_day": bson.M{"$ne": currentDay},
		})
		if err != nil {
			cancel()
			continue
		}

		var feeds []RssFeed
		if err = cursor.All(ctx, &feeds); err != nil {
			cancel()
			continue
		}
		cancel()

		for _, feed := range feeds {
			// Parse schedule times
			if feed.ScheduleTime == currentTime {
				// Run in a separate goroutine to prevent blocking the scheduler
				go func(f RssFeed) {
					err := ScrapeFeed(f)
					if err != nil {
						log.Printf("Scheduler scrape error for %s: %v", f.Name, err)
					}
				}(feed)
			}
		}
	}
}

// Helpers
func parsePubDate(pubDateStr string) time.Time {
	formats := []string{
		time.RFC1123Z,
		time.RFC1123,
		time.RFC3339,
		time.RFC3339Nano,
		"Mon, 02 Jan 2006 15:04:05 MST",
		"Mon, 02 Jan 2006 15:04:05 -0700",
		"2006-01-02T15:04:05Z07:00",
		"2006-01-02 15:04:05",
	}

	for _, fmtStr := range formats {
		t, err := time.Parse(fmtStr, pubDateStr)
		if err == nil {
			return t
		}
	}
	return time.Now()
}

func cleanHTML(s string) string {
	// Simple tags remover
	var builder strings.Builder
	inTag := false
	for _, r := range s {
		if r == '<' {
			inTag = true
			continue
		}
		if r == '>' {
			inTag = false
			continue
		}
		if !inTag {
			builder.WriteRune(r)
		}
	}
	res := builder.String()
	res = strings.ReplaceAll(res, "&nbsp;", " ")
	res = strings.ReplaceAll(res, "&lt;", "<")
	res = strings.ReplaceAll(res, "&gt;", ">")
	res = strings.ReplaceAll(res, "&amp;", "&")
	res = strings.ReplaceAll(res, "&quot;", "\"")
	res = strings.ReplaceAll(res, "&apos;", "'")
	return strings.TrimSpace(res)
}

func truncateText(s string, maxLen int) string {
	runes := []rune(s)
	if len(runes) > maxLen {
		return string(runes[:maxLen]) + "..."
	}
	return s
}

// Gin Handlers for Admin Dashboard API

func GetRssFeeds(c *gin.Context) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cursor, err := RssFeedColl.Find(ctx, bson.M{})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer cursor.Close(ctx)

	var feeds []RssFeed = []RssFeed{}
	if err = cursor.All(ctx, &feeds); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, feeds)
}

func CreateRssFeed(c *gin.Context) {
	var feed RssFeed
	if err := c.ShouldBindJSON(&feed); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	feed.ID = primitive.NewObjectID().Hex()
	feed.CreatedAt = time.Now()

	// Fill model name for display convenience
	if feed.ModelID != "" {
		var model AIModel
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		err := ModelColl.FindOne(ctx, bson.M{"_id": feed.ModelID}).Decode(&model)
		cancel()
		if err == nil {
			feed.ModelName = model.CustomName
		} else {
			// Try matching custom name
			ctx, cancel = context.WithTimeout(context.Background(), 3*time.Second)
			err = ModelColl.FindOne(ctx, bson.M{"custom_name": feed.ModelID}).Decode(&model)
			cancel()
			if err == nil {
				feed.ModelName = model.CustomName
			}
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := RssFeedColl.InsertOne(ctx, feed)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, feed)
}

func UpdateRssFeed(c *gin.Context) {
	id := c.Param("id")
	var feed RssFeed
	if err := c.ShouldBindJSON(&feed); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if feed.ModelID != "" {
		var model AIModel
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		err := ModelColl.FindOne(ctx, bson.M{"_id": feed.ModelID}).Decode(&model)
		cancel()
		if err == nil {
			feed.ModelName = model.CustomName
		} else {
			// Try matching custom name
			ctx, cancel = context.WithTimeout(context.Background(), 3*time.Second)
			err = ModelColl.FindOne(ctx, bson.M{"custom_name": feed.ModelID}).Decode(&model)
			cancel()
			if err == nil {
				feed.ModelName = model.CustomName
			}
		}
	} else {
		feed.ModelName = ""
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	update := bson.M{
		"$set": bson.M{
			"name":          feed.Name,
			"url":           feed.URL,
			"schedule_time": feed.ScheduleTime,
			"model_id":      feed.ModelID,
			"model_name":    feed.ModelName,
		},
	}

	_, err := RssFeedColl.UpdateOne(ctx, bson.M{"_id": id}, update)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	feed.ID = id
	c.JSON(http.StatusOK, feed)
}

func DeleteRssFeed(c *gin.Context) {
	id := c.Param("id")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := RssFeedColl.DeleteOne(ctx, bson.M{"_id": id})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Optionally delete associated articles
	_, _ = RssArticleColl.DeleteMany(ctx, bson.M{"feed_id": id})

	c.JSON(http.StatusOK, gin.H{"message": "RSS feed deleted successfully"})
}

func ScrapeRssFeedHandler(c *gin.Context) {
	id := c.Param("id")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	var feed RssFeed
	err := RssFeedColl.FindOne(ctx, bson.M{"_id": id}).Decode(&feed)
	cancel()
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "RSS Feed not found"})
		return
	}

	// Read optional model_id override from request body
	var reqBody struct {
		ModelID string `json:"model_id"`
	}
	// Ignore error if body is empty or not JSON
	_ = c.ShouldBindJSON(&reqBody)
	if reqBody.ModelID != "" {
		feed.ModelID = reqBody.ModelID
	}

	// Perform scraping
	err = ScrapeFeed(feed)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Scrape failed: " + err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Scrape completed successfully"})
}

func GetRssArticles(c *gin.Context) {
	feedID := c.Query("feed_id")
	filter := bson.M{}
	if feedID != "" {
		filter["feed_id"] = feedID
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	opts := options.Find().SetSort(bson.M{"published_at": -1}).SetLimit(200)
	cursor, err := RssArticleColl.Find(ctx, filter, opts)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer cursor.Close(ctx)

	var articles []RssArticle = []RssArticle{}
	if err = cursor.All(ctx, &articles); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, articles)
}

func DeleteRssArticle(c *gin.Context) {
	id := c.Param("id")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := RssArticleColl.DeleteOne(ctx, bson.M{"_id": id})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Article deleted successfully"})
}

func DeleteAllRssArticles(c *gin.Context) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := RssArticleColl.DeleteMany(ctx, bson.M{})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "All articles deleted successfully"})
}
