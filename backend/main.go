package main

import (
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
)

func CORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Credentials", "true")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, DELETE")

		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}

func main() {
	// Load .env file if it exists
	_ = godotenv.Load()

	// Initialize database
	InitDB()

	// Initialize Gin router
	r := gin.Default()

	// Enable CORS
	r.Use(CORSMiddleware())

	// Public Routes (No auth required)
	r.POST("/api/auth/login", LoginHandler)

	// Mirror Download Proxies (No auth required)
	r.GET("/mirror/gh", GithubMirrorHandler)
	r.GET("/mirror/gh/*url", GithubMirrorHandler)
	r.Any("/mirror/pub/*path", PubMirrorHandler)
	r.Any("/mirror/npm/*path", NpmMirrorHandler)
	r.Any("/mirror/pypi/*path", PipMirrorHandler)

	// OpenAI Gateway (requires Gateway API key, handled inside handler)
	r.POST("/v1/chat/completions", ProxyHandler)
	r.GET("/v1/models", ProxyModelsHandler)

	// Admin Panel APIs (requires JWT authentication)
	admin := r.Group("/api/admin")
	admin.Use(AuthMiddleware())
	{
		// Dashboard Stats
		admin.GET("/stats", GetDashboardStats)

		// Models CRUD
		admin.GET("/models", GetModels)
		admin.POST("/models", CreateModel)
		admin.PUT("/models/:id", UpdateModel)
		admin.DELETE("/models/:id", DeleteModel)

		// API Keys CRUD
		admin.GET("/keys", GetApiKeys)
		admin.POST("/keys", CreateApiKey)
		admin.DELETE("/keys/:id", DeleteApiKey)
	}

	// Get port from env or default
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Server is starting on port %s...", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}
