package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
)

// OpenAIRequest represents the structure of standard chat completion requests
type OpenAIRequest struct {
	Model    string                   `json:"model"`
	Messages []map[string]interface{} `json:"messages"`
	Stream   bool                     `json:"stream,omitempty"`
	// Capture other dynamic fields as well
	ExtraParams map[string]interface{} `json:"-"`
}

func estimatePromptTokens(messages []interface{}) int {
	var totalChars int
	for _, msg := range messages {
		if m, ok := msg.(map[string]interface{}); ok {
			if content, ok := m["content"].(string); ok {
				totalChars += len(content)
			}
		}
	}
	// Estimate: ~3 characters per token for typical code/text mix
	if totalChars == 0 {
		return 0
	}
	tokens := totalChars / 3
	if tokens == 0 {
		return 1
	}
	return tokens
}

func logTokenUsage(apiKeyID, apiKeyName, modelName string, promptTokens, completionTokens, reasoningTokens int, durationMs int64, statusCode int) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	tokenLog := TokenLog{
		ApiKeyID:         apiKeyID,
		ApiKeyName:       apiKeyName,
		ModelName:        modelName,
		PromptTokens:     promptTokens,
		CompletionTokens: completionTokens,
		ReasoningTokens:  reasoningTokens,
		DurationMs:       durationMs,
		StatusCode:       statusCode,
		CreatedAt:        time.Now(),
	}

	_, err := TokenLogColl.InsertOne(ctx, tokenLog)
	if err != nil {
		log.Printf("Failed to insert token log: %v", err)
	}
}

func generateChatID() string {
	b := make([]byte, 12)
	if _, err := rand.Read(b); err != nil {
		return "chatcmpl-unknown"
	}
	return "chatcmpl-" + hex.EncodeToString(b)
}

func normalizeNonStreamResponse(respMap map[string]interface{}, customModelName string) map[string]interface{} {
	if _, ok := respMap["id"]; !ok {
		respMap["id"] = generateChatID()
	}
	respMap["object"] = "chat.completion"
	if created, ok := respMap["created"].(float64); !ok || created == 0 {
		respMap["created"] = time.Now().Unix()
	}
	respMap["model"] = customModelName

	choices, ok := respMap["choices"].([]interface{})
	if !ok {
		choices = []interface{}{}
		respMap["choices"] = choices
	}
	for i, c := range choices {
		choice, ok := c.(map[string]interface{})
		if !ok {
			choice = make(map[string]interface{})
			choices[i] = choice
		}
		if _, hasIdx := choice["index"]; !hasIdx {
			choice["index"] = i
		}
		msg, msgOk := choice["message"].(map[string]interface{})
		if !msgOk {
			msg = make(map[string]interface{})
			choice["message"] = msg
		}
		if _, hasRole := msg["role"]; !hasRole {
			msg["role"] = "assistant"
		}
		if _, hasContent := msg["content"]; !hasContent {
			msg["content"] = ""
		}
		if _, hasLogprobs := choice["logprobs"]; !hasLogprobs {
			choice["logprobs"] = nil
		}
		if _, hasFinish := choice["finish_reason"]; !hasFinish {
			choice["finish_reason"] = "stop"
		}
	}

	if usage, ok := respMap["usage"].(map[string]interface{}); ok {
		if _, ok := usage["prompt_tokens"]; !ok {
			usage["prompt_tokens"] = 0
		}
		if _, ok := usage["completion_tokens"]; !ok {
			usage["completion_tokens"] = 0
		}
		if _, ok := usage["total_tokens"]; !ok {
			pt, _ := usage["prompt_tokens"].(float64)
			ct, _ := usage["completion_tokens"].(float64)
			usage["total_tokens"] = pt + ct
		}
	}

	return respMap
}

func normalizeStreamChunk(chunk map[string]interface{}, customModelName string) map[string]interface{} {
	if _, ok := chunk["id"]; !ok {
		chunk["id"] = generateChatID()
	}
	chunk["object"] = "chat.completion.chunk"
	if created, ok := chunk["created"].(float64); !ok || created == 0 {
		chunk["created"] = time.Now().Unix()
	}
	chunk["model"] = customModelName

	if choices, ok := chunk["choices"].([]interface{}); ok {
		for i, c := range choices {
			choice, ok := c.(map[string]interface{})
			if !ok {
				choice = make(map[string]interface{})
				choices[i] = choice
			}
			if _, hasIdx := choice["index"]; !hasIdx {
				choice["index"] = i
			}
			delta, deltaOk := choice["delta"].(map[string]interface{})
			if !deltaOk {
				delta = make(map[string]interface{})
				choice["delta"] = delta
			}
			if _, hasLogprobs := choice["logprobs"]; !hasLogprobs {
				choice["logprobs"] = nil
			}
		}
	} else {
		chunk["choices"] = []interface{}{}
	}

	return chunk
}

// ProxyHandler proxies the OpenAI requests
func ProxyHandler(c *gin.Context) {
	// 1. Verify Gateway API Key
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header missing"})
		return
	}

	parts := strings.SplitN(authHeader, " ", 2)
	if !(len(parts) == 2 && parts[0] == "Bearer") {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Authorization header format must be Bearer <key>"})
		return
	}

	gatewayKey := parts[1]
	apiKey, err := ValidateGatewayKey(gatewayKey)
	if err != nil || apiKey == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid Workspace API Key"})
		return
	}

	// 2. Parse request body
	bodyBytes, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Failed to read request body"})
		return
	}

	var reqMap map[string]interface{}
	if err := json.Unmarshal(bodyBytes, &reqMap); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid JSON request body"})
		return
	}

	modelName, ok := reqMap["model"].(string)
	if !ok || modelName == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Model parameter is required"})
		return
	}

	// Extract messages to estimate prompt tokens
	var estPromptTokens int
	if msgs, ok := reqMap["messages"].([]interface{}); ok {
		estPromptTokens = estimatePromptTokens(msgs)
	}

	// 3. Find Model Mapping in DB
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var mappedModel AIModel
	err = ModelColl.FindOne(ctx, bson.M{"custom_name": modelName}).Decode(&mappedModel)
	if err != nil {
		// Fallback to checking by ID if custom name didn't match directly
		err = ModelColl.FindOne(ctx, bson.M{"_id": modelName}).Decode(&mappedModel)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Configured model not found in workspace: " + modelName})
			return
		}
	}

	// Rewrite request body with real provider model
	reqMap["model"] = mappedModel.ProviderModel

	// Inject stream_options: include_usage for streaming if requested
	isStream, _ := reqMap["stream"].(bool)
	if isStream {
		streamOpts, ok := reqMap["stream_options"].(map[string]interface{})
		if !ok {
			streamOpts = make(map[string]interface{})
		}
		streamOpts["include_usage"] = true
		reqMap["stream_options"] = streamOpts
	}

	newBodyBytes, err := json.Marshal(reqMap)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to rebuild request"})
		return
	}

	// 4. Perform request forward
	forwardRequest(c, *apiKey, mappedModel, newBodyBytes, estPromptTokens, isStream)
}

func forwardRequest(c *gin.Context, apiKey WorkspaceApiKey, targetModel AIModel, body []byte, estPromptTokens int, isStream bool) {
	startTime := time.Now()
	client := &http.Client{
		Timeout: 5 * time.Minute,
	}

	// Build target URL
	providerBase := strings.TrimSuffix(targetModel.ProviderBaseURL, "/")
	targetURL := providerBase + "/v1/chat/completions"
	if strings.Contains(targetModel.ProviderBaseURL, "/chat/completions") {
		targetURL = targetModel.ProviderBaseURL
	}

	req, err := http.NewRequest("POST", targetURL, bytes.NewBuffer(body))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create forward request: " + err.Error()})
		return
	}

	// Set headers
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+targetModel.ProviderAPIKey)

	// Send Request
	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "Failed to reach model provider: " + err.Error()})
		return
	}
	defer resp.Body.Close()

	// Transfer headers
	for key, values := range resp.Header {
		if key == "Content-Type" || key == "Cache-Control" || key == "Connection" {
			for _, val := range values {
				c.Header(key, val)
			}
		}
	}
	c.Writer.WriteHeader(resp.StatusCode)

	var promptTokens, completionTokens, reasoningTokens int

	if isStream && strings.HasPrefix(resp.Header.Get("Content-Type"), "text/event-stream") {
		var contentChars, reasoningChars int
		var hasUsage bool
		shouldNormalize := targetModel.ResponseFormat == "openai"

		reader := bufio.NewReader(resp.Body)
		for {
			lineBytes, readErr := reader.ReadBytes('\n')
			if len(lineBytes) > 0 {
				line := string(lineBytes)
				trimmed := strings.TrimSpace(line)
				if strings.HasPrefix(trimmed, "data: ") {
					dataStr := strings.TrimPrefix(trimmed, "data: ")
					if dataStr == "[DONE]" {
						_, _ = c.Writer.Write(lineBytes)
					} else {
						var chunk map[string]interface{}
						if err := json.Unmarshal([]byte(dataStr), &chunk); err == nil {
							if shouldNormalize {
								chunk = normalizeStreamChunk(chunk, targetModel.CustomName)
							}

							if usage, ok := chunk["usage"].(map[string]interface{}); ok {
								hasUsage = true
								if pt, ok := usage["prompt_tokens"].(float64); ok {
									promptTokens = int(pt)
								}
								if ct, ok := usage["completion_tokens"].(float64); ok {
									completionTokens = int(ct)
								}
								if details, ok := usage["completion_tokens_details"].(map[string]interface{}); ok {
									if rt, ok := details["reasoning_tokens"].(float64); ok {
										reasoningTokens = int(rt)
									}
								} else if rt, ok := usage["reasoning_tokens"].(float64); ok {
									reasoningTokens = int(rt)
								}
							}

							if choices, ok := chunk["choices"].([]interface{}); ok && len(choices) > 0 {
								if choice, ok := choices[0].(map[string]interface{}); ok {
									if delta, ok := choice["delta"].(map[string]interface{}); ok {
										if content, ok := delta["content"].(string); ok {
											contentChars += len(content)
										}
										if reasoning, ok := delta["reasoning_content"].(string); ok {
											reasoningChars += len(reasoning)
										}
									}
								}
							}

							normalizedData, _ := json.Marshal(chunk)
							c.Writer.WriteString("data: " + string(normalizedData) + "\n\n")
						} else {
							_, _ = c.Writer.Write(lineBytes)
						}
					}
				} else {
					_, _ = c.Writer.Write(lineBytes)
				}
				c.Writer.Flush()
			}
			if readErr != nil {
				break
			}
		}

		if !hasUsage {
			promptTokens = estPromptTokens
			completionTokens = contentChars / 3
			reasoningTokens = reasoningChars / 3
			completionTokens += reasoningTokens
		}
	} else {
		// Non-streaming response
		respBytes, readErr := io.ReadAll(resp.Body)
		if readErr == nil {
			shouldNormalize := targetModel.ResponseFormat == "openai"

			var respMap map[string]interface{}
			if err := json.Unmarshal(respBytes, &respMap); err == nil {
				if shouldNormalize {
					respMap = normalizeNonStreamResponse(respMap, targetModel.CustomName)
				}

				normalizedBytes, _ := json.Marshal(respMap)
				_, _ = c.Writer.Write(normalizedBytes)

				var hasUsage bool
				if usage, ok := respMap["usage"].(map[string]interface{}); ok {
					hasUsage = true
					if pt, ok := usage["prompt_tokens"].(float64); ok {
						promptTokens = int(pt)
					}
					if ct, ok := usage["completion_tokens"].(float64); ok {
						completionTokens = int(ct)
					}
					if details, ok := usage["completion_tokens_details"].(map[string]interface{}); ok {
						if rt, ok := details["reasoning_tokens"].(float64); ok {
							reasoningTokens = int(rt)
						}
					} else if rt, ok := usage["reasoning_tokens"].(float64); ok {
						reasoningTokens = int(rt)
					}
				}

				if !hasUsage {
					promptTokens = estPromptTokens
					if choices, ok := respMap["choices"].([]interface{}); ok && len(choices) > 0 {
						if choice, ok := choices[0].(map[string]interface{}); ok {
							if msg, ok := choice["message"].(map[string]interface{}); ok {
								if content, ok := msg["content"].(string); ok {
									completionTokens = len(content) / 3
								}
								if reasoning, ok := msg["reasoning_content"].(string); ok {
									reasoningTokens = len(reasoning) / 3
									completionTokens += reasoningTokens
								}
							}
						}
					}
				}
			} else {
				_, _ = c.Writer.Write(respBytes)
			}
		}
	}

	duration := time.Since(startTime).Milliseconds()
	// Record token usage in DB asynchronously
	go logTokenUsage(apiKey.ID, apiKey.Name, targetModel.CustomName, promptTokens, completionTokens, reasoningTokens, duration, resp.StatusCode)
}

// ProxyModelsHandler mimics the OpenAI list models endpoint
func ProxyModelsHandler(c *gin.Context) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cursor, err := ModelColl.Find(ctx, bson.M{})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer cursor.Close(ctx)

	var models []AIModel
	if err = cursor.All(ctx, &models); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	type OpenAIModelItem struct {
		ID      string `json:"id"`
		Object  string `json:"object"`
		Created int64  `json:"created"`
		OwnedBy string `json:"owned_by"`
	}

	type OpenAIModelList struct {
		Object string            `json:"object"`
		Data   []OpenAIModelItem `json:"data"`
	}

	list := OpenAIModelList{
		Object: "list",
		Data:   []OpenAIModelItem{},
	}

	for _, m := range models {
		list.Data = append(list.Data, OpenAIModelItem{
			ID:      m.CustomName,
			Object:  "model",
			Created: m.CreatedAt.Unix(),
			OwnedBy: "relais-workspace",
		})
	}

	c.JSON(http.StatusOK, list)
}
