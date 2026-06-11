package main

import (
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// proxyRequest copies headers and forwards the request to the target URL
func proxyRequest(c *gin.Context, targetURL string) {
	client := &http.Client{
		Timeout: 30 * time.Minute, // Long timeout for large packages
	}

	req, err := http.NewRequest(c.Request.Method, targetURL, c.Request.Body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create proxy request: " + err.Error()})
		return
	}

	// Copy headers
	for key, values := range c.Request.Header {
		if key != "Host" && key != "Authorization" {
			for _, val := range values {
				req.Header.Add(key, val)
			}
		}
	}

	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "Proxy destination unreachable: " + err.Error()})
		return
	}
	defer resp.Body.Close()

	// Copy response headers
	for key, values := range resp.Header {
		if key != "Access-Control-Allow-Origin" {
			for _, val := range values {
				c.Header(key, val)
			}
		}
	}
	c.Writer.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(c.Writer, resp.Body)
}

// GithubMirrorHandler handles GitHub proxies (releases and raw files)
func GithubMirrorHandler(c *gin.Context) {
	targetURL := c.Query("url")
	if targetURL == "" {
		targetURL = c.Param("url")
	}

	targetURL = strings.TrimPrefix(targetURL, "/")

	if targetURL == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "url parameter is required"})
		return
	}

	// Safety check
	if !strings.Contains(targetURL, "github.com") && !strings.Contains(targetURL, "githubusercontent.com") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Only GitHub URLs are allowed for mirror proxy"})
		return
	}

	proxyRequest(c, targetURL)
}

// PubMirrorHandler proxies Flutter/Dart Pub packages
func PubMirrorHandler(c *gin.Context) {
	path := c.Param("path")
	targetURL := "https://pub.dev" + path
	proxyRequest(c, targetURL)
}

// NpmMirrorHandler proxies NPM packages
func NpmMirrorHandler(c *gin.Context) {
	path := c.Param("path")
	targetURL := "https://registry.npmjs.org" + path
	proxyRequest(c, targetURL)
}

// PipMirrorHandler proxies Python Pip index and files
func PipMirrorHandler(c *gin.Context) {
	path := c.Param("path")
	// If path contains files.pythonhosted.org (used for source downloads)
	if strings.HasPrefix(path, "/packages/") {
		targetURL := "https://files.pythonhosted.org" + path
		proxyRequest(c, targetURL)
		return
	}
	targetURL := "https://pypi.org" + path
	proxyRequest(c, targetURL)
}
