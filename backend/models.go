package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"io"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
)

// GenerateRandomKey generates a secure random API key prefix with wk-
func GenerateRandomKey() string {
	b := make([]byte, 24)
	if _, err := rand.Read(b); err != nil {
		return ""
	}
	return "wk-" + hex.EncodeToString(b)
}

// Model Handlers

func GetModels(c *gin.Context) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cursor, err := ModelColl.Find(ctx, bson.M{})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer cursor.Close(ctx)

	var models []AIModel = []AIModel{}
	if err = cursor.All(ctx, &models); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, models)
}

func CreateModel(c *gin.Context) {
	var model AIModel
	if err := c.ShouldBindJSON(&model); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	model.ID = primitive.NewObjectID().Hex()
	model.CreatedAt = time.Now()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := ModelColl.InsertOne(ctx, model)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, model)
}

func UpdateModel(c *gin.Context) {
	id := c.Param("id")
	var model AIModel
	if err := c.ShouldBindJSON(&model); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	update := bson.M{
		"$set": bson.M{
			"custom_name":       model.CustomName,
			"provider_base_url": model.ProviderBaseURL,
			"provider_api_key":  model.ProviderAPIKey,
			"provider_model":    model.ProviderModel,
		},
	}

	_, err := ModelColl.UpdateOne(ctx, bson.M{"_id": id}, update)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	model.ID = id
	c.JSON(http.StatusOK, model)
}

func DeleteModel(c *gin.Context) {
	id := c.Param("id")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := ModelColl.DeleteOne(ctx, bson.M{"_id": id})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Model deleted successfully"})
}

// Workspace API Key Handlers

func GetApiKeys(c *gin.Context) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	cursor, err := ApiKeyColl.Find(ctx, bson.M{})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer cursor.Close(ctx)

	var keys []WorkspaceApiKey = []WorkspaceApiKey{}
	if err = cursor.All(ctx, &keys); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, keys)
}

func CreateApiKey(c *gin.Context) {
	var body struct {
		Name string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	key := WorkspaceApiKey{
		ID:        primitive.NewObjectID().Hex(),
		Name:      body.Name,
		Key:       GenerateRandomKey(),
		CreatedAt: time.Now(),
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := ApiKeyColl.InsertOne(ctx, key)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, key)
}

func DeleteApiKey(c *gin.Context) {
	id := c.Param("id")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err := ApiKeyColl.DeleteOne(ctx, bson.M{"_id": id})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "API Key deleted successfully"})
}

// Helper to validate a gateway API key
func ValidateGatewayKey(keyStr string) (*WorkspaceApiKey, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	var result WorkspaceApiKey
	err := ApiKeyColl.FindOne(ctx, bson.M{"key": keyStr}).Decode(&result)
	if err != nil {
		return nil, err
	}
	return &result, nil
}

// GetKiloModels fetches models from kilo.ai and proxies them back to the frontend
func GetKiloModels(c *gin.Context) {
	resp, err := http.Get("https://api.kilo.ai/api/gateway/models")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch Kilo models: " + err.Error()})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		c.JSON(resp.StatusCode, gin.H{"error": "Upstream error fetching Kilo models"})
		return
	}

	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to read response body: " + err.Error()})
		return
	}

	c.Data(http.StatusOK, "application/json", bodyBytes)
}


