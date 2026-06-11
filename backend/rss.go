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
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo/options"
	"golang.org/x/net/html"
	"net/url"
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

		// Fetch full article content from target URL
		extractedContent, err := fetchAndExtractContent(art.URL)
		if err != nil {
			log.Printf("Failed to fetch full article content for %s: %v", art.URL, err)
			extractedContent = art.Summary // fallback to summary
		}
		art.Content = extractedContent

		// Generate AI Summary if a model is mapped
		if targetModel != nil {
			summaryText, err := generateAISummary(targetModel, art.Title, art.Content)
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

// fetchAndExtractContent fetches the target URL and extracts clean article text
func fetchAndExtractContent(targetURL string) (string, error) {
	client := &http.Client{
		Timeout: 15 * time.Second,
	}

	req, err := http.NewRequest("GET", targetURL, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("status code %d", resp.StatusCode)
	}

	doc, err := html.Parse(resp.Body)
	if err != nil {
		return "", err
	}

	var bodyText strings.Builder
	
	// Helper to check if node is inside script, style, nav, header, footer, form, aside, noscript
	var checkIgnoreTags = func(n *html.Node) bool {
		if n.Type == html.ElementNode {
			tag := strings.ToLower(n.Data)
			if tag == "script" || tag == "style" || tag == "nav" || tag == "header" || 
				tag == "footer" || tag == "aside" || tag == "form" || tag == "noscript" || 
				tag == "iframe" || tag == "button" || tag == "select" || tag == "option" {
				return true
			}
		}
		return false
	}

	// Find the <article> node first
	var articleNode *html.Node
	var findArticle func(*html.Node)
	findArticle = func(n *html.Node) {
		if n.Type == html.ElementNode && strings.ToLower(n.Data) == "article" {
			articleNode = n
			return
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			findArticle(c)
			if articleNode != nil {
				return
			}
		}
	}
	findArticle(doc)

	var startNode *html.Node = doc
	if articleNode != nil {
		startNode = articleNode
	}

	var f func(*html.Node)
	f = func(n *html.Node) {
		if checkIgnoreTags(n) {
			return
		}
		if n.Type == html.TextNode {
			text := strings.TrimSpace(n.Data)
			if text != "" {
				bodyText.WriteString(text)
				bodyText.WriteString("\n")
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			f(c)
		}
	}
	f(startNode)

	// Clean up extra whitespace and limit length
	lines := strings.Split(bodyText.String(), "\n")
	var cleanedLines []string
	for _, l := range lines {
		l = strings.TrimSpace(l)
		if l != "" {
			cleanedLines = append(cleanedLines, l)
		}
	}

	res := strings.Join(cleanedLines, "\n\n")
	if len(res) > 15000 {
		runes := []rune(res)
		if len(runes) > 15000 {
			res = string(runes[:15000]) + "..."
		}
	}

	return res, nil
}

// generateAISummaryStream generates AI summary by streaming from provider
func generateAISummaryStream(model *AIModel, title, content string, onChunk func(string)) (string, error) {
	log.Printf("Requesting streaming AI summary from model: %s", model.CustomName)

	promptContent := fmt.Sprintf("标题: %s\n内容: %s", title, content)
	systemMessage := "你是一个专业的多语言新闻翻译与摘要助手。请将提供的新闻内容翻译并总结为一段精炼的简体中文摘要，字数控制在150字以内，保留核心事实与观点。无论输入内容是何种语言（如英文），最终的摘要产物必须是简体中文。"

	requestBody := map[string]interface{}{
		"model": model.ProviderModel,
		"messages": []map[string]interface{}{
			{"role": "system", "content": systemMessage},
			{"role": "user", "content": promptContent},
		},
		"stream": true,
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

	var fullSummary strings.Builder
	reader := io.Reader(resp.Body)
	
	var lineBuffer []byte
	buf := make([]byte, 1024)
	for {
		n, err := reader.Read(buf)
		if n > 0 {
			lineBuffer = append(lineBuffer, buf[:n]...)
			for {
				lineIdx := bytes.IndexByte(lineBuffer, '\n')
				if lineIdx == -1 {
					break
				}
				line := lineBuffer[:lineIdx]
				lineBuffer = lineBuffer[lineIdx+1:]
				
				lineStr := strings.TrimSpace(string(line))
				if lineStr == "" {
					continue
				}
				if !strings.HasPrefix(lineStr, "data: ") {
					continue
				}
				
				dataPayload := strings.TrimPrefix(lineStr, "data: ")
				if dataPayload == "[DONE]" {
					break
				}
				
				var chunk map[string]interface{}
				if err := json.Unmarshal([]byte(dataPayload), &chunk); err == nil {
					if choices, ok := chunk["choices"].([]interface{}); ok && len(choices) > 0 {
						if choiceMap, ok := choices[0].(map[string]interface{}); ok {
							if delta, ok := choiceMap["delta"].(map[string]interface{}); ok {
								if contentChunk, ok := delta["content"].(string); ok && contentChunk != "" {
									fullSummary.WriteString(contentChunk)
									if onChunk != nil {
										onChunk(contentChunk)
									}
								}
							}
						}
					}
				}
			}
		}
		if err != nil {
			if err == io.EOF {
				break
			}
			return "", err
		}
	}

	return strings.TrimSpace(fullSummary.String()), nil
}

// ScrapingTask tracks active scraping tasks
type ScrapingTask struct {
	FeedID    string
	FeedName  string
	Status    string // "running", "completed", "failed"
	mu        sync.Mutex
	listeners map[chan string]bool
}

func (t *ScrapingTask) Broadcast(event string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	for ch := range t.listeners {
		select {
		case ch <- event:
		default:
		}
	}
}

func (t *ScrapingTask) AddListener(ch chan string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.listeners[ch] = true
}

func (t *ScrapingTask) RemoveListener(ch chan string) {
	t.mu.Lock()
	defer t.mu.Unlock()
	delete(t.listeners, ch)
}

func (t *ScrapingTask) SendStatus(message string) {
	payload, _ := json.Marshal(map[string]string{
		"type":    "status",
		"message": message,
	})
	t.Broadcast(string(payload))
}

func (t *ScrapingTask) SendArticleStart(title string) {
	payload, _ := json.Marshal(map[string]string{
		"type":  "article_start",
		"title": title,
	})
	t.Broadcast(string(payload))
}

func (t *ScrapingTask) SendAiChunk(chunk string) {
	payload, _ := json.Marshal(map[string]string{
		"type":  "ai_chunk",
		"chunk": chunk,
	})
	t.Broadcast(string(payload))
}

func (t *ScrapingTask) SendArticleEnd(aiSummary string) {
	payload, _ := json.Marshal(map[string]string{
		"type":       "article_end",
		"ai_summary": aiSummary,
	})
	t.Broadcast(string(payload))
}

func (t *ScrapingTask) SendDone(newCount int) {
	payload, _ := json.Marshal(map[string]interface{}{
		"type":      "done",
		"new_count": newCount,
	})
	t.Broadcast(string(payload))
}

func (t *ScrapingTask) SendError(errMsg string) {
	payload, _ := json.Marshal(map[string]string{
		"type":  "error",
		"error": errMsg,
	})
	t.Broadcast(string(payload))
}

var (
	activeTasks   = make(map[string]*ScrapingTask)
	activeTasksMu sync.Mutex
)

// ScrapeRssFeedStreamHandler is SSE endpoint for streaming scraping progress
func ScrapeRssFeedStreamHandler(c *gin.Context) {
	id := c.Param("id")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	var feed RssFeed
	err := RssFeedColl.FindOne(ctx, bson.M{"_id": id}).Decode(&feed)
	cancel()
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "RSS Feed not found"})
		return
	}

	modelIDOverride := c.Query("model_id")
	if modelIDOverride != "" {
		feed.ModelID = modelIDOverride
	}

	activeTasksMu.Lock()
	task, exists := activeTasks[id]
	if !exists {
		task = &ScrapingTask{
			FeedID:    id,
			FeedName:  feed.Name,
			Status:    "running",
			listeners: make(map[chan string]bool),
		}
		activeTasks[id] = task
		activeTasksMu.Unlock()

		go runBackgroundScrape(task, feed)
	} else {
		activeTasksMu.Unlock()
	}

	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")
	c.Writer.Header().Set("Transfer-Encoding", "chunked")

	listenerChan := make(chan string, 100)
	task.AddListener(listenerChan)
	defer func() {
		task.RemoveListener(listenerChan)
		close(listenerChan)
	}()

	c.SSEvent("status", "connected")
	c.Writer.Flush()

	clientGone := c.Writer.CloseNotify()
	for {
		select {
		case <-clientGone:
			return
		case msg, ok := <-listenerChan:
			if !ok {
				return
			}
			c.SSEvent("message", msg)
			c.Writer.Flush()

			var msgMap map[string]interface{}
			if err := json.Unmarshal([]byte(msg), &msgMap); err == nil {
				if t, ok := msgMap["type"].(string); ok && (t == "done" || t == "error") {
					return
				}
			}
		}
	}
}

func runBackgroundScrape(task *ScrapingTask, feed RssFeed) {
	defer func() {
		activeTasksMu.Lock()
		delete(activeTasks, task.FeedID)
		activeTasksMu.Unlock()
	}()

	task.SendStatus("正在拉取 RSS XML 数据...")

	client := &http.Client{
		Timeout: 30 * time.Second,
	}

	req, err := http.NewRequest("GET", feed.URL, nil)
	if err != nil {
		task.SendError("创建请求失败: " + err.Error())
		return
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

	resp, err := client.Do(req)
	if err != nil {
		task.SendError("获取 RSS 链接失败: " + err.Error())
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		task.SendError(fmt.Sprintf("HTTP 错误码: %d", resp.StatusCode))
		return
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		task.SendError("读取 RSS 数据失败: " + err.Error())
		return
	}

	var articles []RssArticle

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
			task.SendError("解析 RSS/Atom XML 失败，格式不受支持")
			return
		}
	}

	task.SendStatus(fmt.Sprintf("成功解析到 %d 篇文章，正在对比排重...", len(articles)))

	var targetModel *AIModel
	if feed.ModelID != "" {
		var model AIModel
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		err = ModelColl.FindOne(ctx, bson.M{"_id": feed.ModelID}).Decode(&model)
		cancel()
		if err == nil {
			targetModel = &model
		} else {
			ctx, cancel = context.WithTimeout(context.Background(), 5*time.Second)
			err = ModelColl.FindOne(ctx, bson.M{"custom_name": feed.ModelID}).Decode(&model)
			cancel()
			if err == nil {
				targetModel = &model
			}
		}
	}

	newCount := 0
	for _, art := range articles {
		if art.URL == "" {
			continue
		}

		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		existsCount, err := RssArticleColl.CountDocuments(ctx, bson.M{"url": art.URL})
		cancel()
		if err == nil && existsCount > 0 {
			continue
		}

		task.SendArticleStart(art.Title)

		task.SendStatus("正在抓取网页正文...")
		extractedContent, err := fetchAndExtractContent(art.URL)
		if err != nil {
			log.Printf("Failed to fetch full article content for %s: %v", art.URL, err)
			extractedContent = art.Summary
		}
		art.Content = extractedContent

		if targetModel != nil {
			task.SendStatus("正在生成 AI 摘要...")
			summaryText, err := generateAISummaryStream(targetModel, art.Title, art.Content, func(chunk string) {
				task.SendAiChunk(chunk)
			})
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

		task.SendArticleEnd(art.AISummary)

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

	task.SendStatus(fmt.Sprintf("抓取完成，共新增入库 %d 篇文章", newCount))

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, _ = RssFeedColl.UpdateOne(ctx, bson.M{"_id": feed.ID}, bson.M{
		"$set": bson.M{
			"last_scraped_at":  time.Now(),
			"last_scraped_day": time.Now().Format("2006-01-02"),
		},
	})

	task.SendDone(newCount)
}

// RssUrlProxyHandler proxies an external web page, injecting <base> tag and stripping security headers to bypass iframe restriction
func RssUrlProxyHandler(c *gin.Context) {
	targetURL := c.Query("url")
	if targetURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "url parameter is required"})
		return
	}

	client := &http.Client{
		Timeout: 15 * time.Second,
	}

	req, err := http.NewRequest("GET", targetURL, nil)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid url: " + err.Error()})
		return
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8")

	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to fetch URL: " + err.Error()})
		return
	}
	defer resp.Body.Close()

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to read website body"})
		return
	}

	baseURI := targetURL
	if parsed, err := url.Parse(targetURL); err == nil {
		baseURI = parsed.Scheme + "://" + parsed.Host + "/"
	}

	contentType := resp.Header.Get("Content-Type")
	if contentType == "" {
		contentType = "text/html; charset=utf-8"
	}

	if strings.Contains(strings.ToLower(contentType), "html") {
		htmlStr := string(bodyBytes)
		baseTag := fmt.Sprintf(`<base href="%s">`, baseURI)
		
		headIdx := strings.Index(strings.ToLower(htmlStr), "<head>")
		if headIdx != -1 {
			htmlStr = htmlStr[:headIdx+6] + baseTag + htmlStr[headIdx+6:]
		} else {
			htmlStr = baseTag + htmlStr
		}
		bodyBytes = []byte(htmlStr)
	}

	c.Writer.Header().Set("Content-Type", contentType)
	c.Writer.Header().Del("X-Frame-Options")
	c.Writer.Header().Del("Content-Security-Policy")
	c.Writer.Header().Del("X-Content-Security-Policy")
	c.Writer.Header().Del("X-WebKit-CSP")
	c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
	
	c.Data(resp.StatusCode, contentType, bodyBytes)
}
