package main

import (
	"context"
	"log"
	"os"
	"time"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

var (
	MongoClient  *mongo.Client
	DB           *mongo.Database
	ModelColl    *mongo.Collection
	ApiKeyColl   *mongo.Collection
	TokenLogColl *mongo.Collection
)

type TokenLog struct {
	ID               string    `bson:"_id,omitempty" json:"id"`
	ApiKeyID         string    `bson:"api_key_id" json:"api_key_id"`
	ApiKeyName       string    `bson:"api_key_name" json:"api_key_name"`
	ModelName        string    `bson:"model_name" json:"model_name"`
	PromptTokens     int       `bson:"prompt_tokens" json:"prompt_tokens"`
	CompletionTokens int       `bson:"completion_tokens" json:"completion_tokens"`
	ReasoningTokens  int       `bson:"reasoning_tokens" json:"reasoning_tokens"`
	DurationMs       int64     `bson:"duration_ms" json:"duration_ms"`
	StatusCode       int       `bson:"status_code" json:"status_code"`
	CreatedAt        time.Time `bson:"created_at" json:"created_at"`
}

type AIModel struct {
	ID               string    `bson:"_id,omitempty" json:"id"`
	CustomName       string    `bson:"custom_name" json:"custom_name"`               // Custom model name presented to the client
	ProviderBaseURL  string    `bson:"provider_base_url" json:"provider_base_url"`   // e.g. https://api.openai.com
	ProviderAPIKey   string    `bson:"provider_api_key" json:"provider_api_key"`     // e.g. sk-xxxx
	ProviderModel    string    `bson:"provider_model" json:"provider_model"`         // Real provider model e.g. gpt-4o
	CreatedAt        time.Time `bson:"created_at" json:"created_at"`
}

type WorkspaceApiKey struct {
	ID        string    `bson:"_id,omitempty" json:"id"`
	Name      string    `bson:"name" json:"name"` // Description or name of the key
	Key       string    `bson:"key" json:"key"`   // The actual workspace gateway key e.g. wk-xxxx
	CreatedAt time.Time `bson:"created_at" json:"created_at"`
}

func InitDB() {
	mongoURI := os.Getenv("MONGO_URI")
	if mongoURI == "" {
		mongoURI = "mongodb://localhost:27017"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(mongoURI))
	if err != nil {
		log.Fatalf("Failed to connect to MongoDB: %v", err)
	}

	err = client.Ping(ctx, nil)
	if err != nil {
		log.Fatalf("Failed to ping MongoDB: %v", err)
	}

	MongoClient = client
	DB = client.Database("workspace")
	ModelColl = DB.Collection("models")
	ApiKeyColl = DB.Collection("api_keys")
	TokenLogColl = DB.Collection("token_logs")

	log.Println("Successfully connected to MongoDB database.")
}
