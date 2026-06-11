package main

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// GetDashboardStats aggregates all token statistics, trends, distributions, and logs
func GetDashboardStats(c *gin.Context) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// 1. Get Summary Stats
	summaryPipeline := []bson.M{
		{
			"$group": bson.M{
				"_id":              nil,
				"total_prompt":     bson.M{"$sum": "$prompt_tokens"},
				"total_completion": bson.M{"$sum": "$completion_tokens"},
				"total_reasoning":  bson.M{"$sum": "$reasoning_tokens"},
				"total_requests":   bson.M{"$sum": 1},
				"success_requests": bson.M{
					"$sum": bson.M{
						"$cond": []interface{}{
							bson.M{"$lt": []interface{}{"$status_code", 400}},
							1,
							0,
						},
					},
				},
			},
		},
	}

	cursor, err := TokenLogColl.Aggregate(ctx, summaryPipeline)
	var summaryResult []bson.M
	if err == nil {
		_ = cursor.All(ctx, &summaryResult)
	}

	var totalPrompt, totalCompletion, totalReasoning, totalRequests, successRequests int
	if len(summaryResult) > 0 {
		r := summaryResult[0]
		// Safely extract integers since MongoDB returns different numeric types depending on driver
		if tp, ok := r["total_prompt"].(int32); ok {
			totalPrompt = int(tp)
		} else if tp, ok := r["total_prompt"].(int64); ok {
			totalPrompt = int(tp)
		}
		if tc, ok := r["total_completion"].(int32); ok {
			totalCompletion = int(tc)
		} else if tc, ok := r["total_completion"].(int64); ok {
			totalCompletion = int(tc)
		}
		if tr, ok := r["total_reasoning"].(int32); ok {
			totalReasoning = int(tr)
		} else if tr, ok := r["total_reasoning"].(int64); ok {
			totalReasoning = int(tr)
		}
		if trq, ok := r["total_requests"].(int32); ok {
			totalRequests = int(trq)
		} else if trq, ok := r["total_requests"].(int64); ok {
			totalRequests = int(trq)
		}
		if srq, ok := r["success_requests"].(int32); ok {
			successRequests = int(srq)
		} else if srq, ok := r["success_requests"].(int64); ok {
			successRequests = int(srq)
		}
	}

	modelCount, _ := ModelColl.CountDocuments(ctx, bson.M{})
	keyCount, _ := ApiKeyColl.CountDocuments(ctx, bson.M{})

	// 2. Trend Data (Last 7 Days)
	trendPipeline := []bson.M{
		{
			"$match": bson.M{
				"created_at": bson.M{"$gte": time.Now().AddDate(0, 0, -7)},
			},
		},
		{
			"$group": bson.M{
				"_id": bson.M{
					"$dateToString": bson.M{
						"format": "%Y-%m-%d",
						"date":   "$created_at",
					},
				},
				"prompt_tokens":     bson.M{"$sum": "$prompt_tokens"},
				"completion_tokens": bson.M{"$sum": "$completion_tokens"},
				"reasoning_tokens":  bson.M{"$sum": "$reasoning_tokens"},
				"requests":          bson.M{"$sum": 1},
			},
		},
		{
			"$sort": bson.M{"_id": 1},
		},
	}
	trendCursor, err := TokenLogColl.Aggregate(ctx, trendPipeline)
	var trends []bson.M = []bson.M{}
	if err == nil {
		_ = trendCursor.All(ctx, &trends)
	}

	// 3. Model Distribution
	modelPipeline := []bson.M{
		{
			"$group": bson.M{
				"_id":          "$model_name",
				"total_tokens": bson.M{"$sum": bson.M{"$add": []interface{}{"$prompt_tokens", "$completion_tokens"}}},
				"requests":     bson.M{"$sum": 1},
			},
		},
		{
			"$sort": bson.M{"total_tokens": -1},
		},
	}
	modelCursor, err := TokenLogColl.Aggregate(ctx, modelPipeline)
	var models []bson.M = []bson.M{}
	if err == nil {
		_ = modelCursor.All(ctx, &models)
	}

	// 4. API Key Distribution
	keyPipeline := []bson.M{
		{
			"$group": bson.M{
				"_id":          "$api_key_name",
				"total_tokens": bson.M{"$sum": bson.M{"$add": []interface{}{"$prompt_tokens", "$completion_tokens"}}},
				"requests":     bson.M{"$sum": 1},
			},
		},
		{
			"$sort": bson.M{"total_tokens": -1},
		},
	}
	keyCursor, err := TokenLogColl.Aggregate(ctx, keyPipeline)
	var keys []bson.M = []bson.M{}
	if err == nil {
		_ = keyCursor.All(ctx, &keys)
	}

	// 5. Recent Logs (Last 20)
	opts := options.Find().SetSort(bson.M{"created_at": -1}).SetLimit(20)
	logsCursor, err := TokenLogColl.Find(ctx, bson.M{}, opts)
	var logs []TokenLog = []TokenLog{}
	if err == nil {
		_ = logsCursor.All(ctx, &logs)
	}

	c.JSON(http.StatusOK, gin.H{
		"summary": gin.H{
			"total_prompt":     totalPrompt,
			"total_completion": totalCompletion,
			"total_reasoning":  totalReasoning,
			"total_requests":   totalRequests,
			"success_requests": successRequests,
			"model_count":      modelCount,
			"key_count":        keyCount,
		},
		"trends":  trends,
		"models":  models,
		"keys":    keys,
		"logs":    logs,
	})
}
