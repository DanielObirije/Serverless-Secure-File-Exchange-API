package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type Config struct {
	BucketName         string
	Region             string
	UploadExpiration   time.Duration
	DownloadExpiration time.Duration
	MaxFileSize        int64
	AllowedExtensions  map[string]bool
}

var (
	cfg           *Config
	s3Client      *s3.Client
	presignClient *s3.PresignClient
)

type UploadUrlRequest struct {
	Filename string `json:"filename"`
}

type UploadUrlResponse struct {
	UploadURL string `json:"uploadUrl"`
	Key       string `json:"key"`
	ExpiresIn int64  `json:"expiresIn"`
}

type DownloadUrlRequest struct {
	Key string `json:"key"`
}

type DownloadUrlResponse struct {
	DownloadURL string `json:"downloadUrl"`
	ExpiresIn   int64  `json:"expiresIn"`
}

type ErrorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message,omitempty"`
}

func init() {
	bucketName := os.Getenv("BUCKET_NAME")
	if bucketName == "" {
		log.Fatal("BUCKET_NAME environment variable is required")
	}
	region := os.Getenv("APP_AWS_REGION")
	if region == "" {
		region = "us-east-1"
	}

	cfg = &Config{
		BucketName:         bucketName,
		Region:             region,
		UploadExpiration:   15 * time.Minute,
		DownloadExpiration: 5 * time.Minute,
		MaxFileSize:        10 * 1024 * 1024,
		AllowedExtensions: map[string]bool{
			"pdf":  true,
			"png":  true,
			"jpg":  true,
			"jpeg": true,
			"docx": true,
		},
	}
	awsCfg, err := config.LoadDefaultConfig(
		context.Background(),
		config.WithRegion(region),
	)
	if err != nil {
		log.Fatalf("failed to load AWS config: %v", err)
	}

	s3Client = s3.NewFromConfig(awsCfg)
	presignClient = s3.NewPresignClient(s3Client)
}

func handler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {

	log.Printf("Received request: %s %s", request.HTTPMethod, request.Path)

	switch {
	case request.Path == "/health" && request.HTTPMethod == "GET":
		return handleHealth()
	case request.Path == "/upload-url" && request.HTTPMethod == "POST":
		return handleUploadUrl(ctx, request)
	case request.Path == "/download-url" && request.HTTPMethod == "POST":
		return handleDownloadUrl(ctx, request)
	default:
		return events.APIGatewayProxyResponse{
			StatusCode: 404,
			Body:       `{"error": "Not Found"}`,
			Headers: map[string]string{
				"Content-Type":                "application/json",
				"Access-Control-Allow-Origin": "*",
			},
		}, nil
	}
}

func handleHealth() (events.APIGatewayProxyResponse, error) {
	response := map[string]interface{}{
		"status":      "healthy",
		"service":     "presigned-url-generator",
		"timestamp":   time.Now().Unix(),
		"bucket":      cfg.BucketName,
		"region":      cfg.Region,
		"maxFileSize": cfg.MaxFileSize,
	}

	body, err := json.Marshal(response)
	if err != nil {
		return errorResponse(500, "Internal error", err), nil
	}
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(body),
		Headers: map[string]string{
			"Content-Type":                "application/json",
			"Access-Control-Allow-Origin": "*",
		},
	}, nil

}

func handleUploadUrl(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	var req UploadUrlRequest

	if err := json.Unmarshal([]byte(request.Body), &req); err != nil {
		return errorResponse(400, "Invalid request body", err), nil
	}

	filename := path.Base(req.Filename)
	if filename == "." || filename == "" {
		return errorResponse(400, "filename is required", nil), nil
	}

	ext := getFileExtension(filename)

	if ext == "" {
		return errorResponse(400, "File must have an extension", nil), nil
	}

	if !cfg.AllowedExtensions[ext] {
		return errorResponse(400, fmt.Sprintf("File extension .%s not allowed. Allowed: %v", ext, getAllowedExtensionList(cfg.AllowedExtensions)), nil), nil
	}

	fileID := uuid.New().String()
	key := fmt.Sprintf("uploads/%s/%s", fileID, filename)

	result, err := presignClient.PresignPutObject(
		ctx,
		&s3.PutObjectInput{
			Bucket: aws.String(cfg.BucketName),
			Key:    aws.String(key),
		},
		func(opts *s3.PresignOptions) {
			opts.Expires = cfg.UploadExpiration
		},
	)

	if err != nil {
		log.Printf("Failed to generate upload presigned URL: %v", err)
		return errorResponse(500, "Failed to generate upload URL", err), nil
	}

	presignedURL := result.URL

	response := UploadUrlResponse{
		UploadURL: presignedURL,
		Key:       key,
		ExpiresIn: int64(cfg.UploadExpiration.Seconds()),
	}

	body, err := json.Marshal(response)
	if err != nil {
		return errorResponse(500, "Internal error", err), nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(body),
		Headers: map[string]string{
			"Content-Type":                "application/json",
			"Access-Control-Allow-Origin": "*",
		},
	}, nil
}

func handleDownloadUrl(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	var req DownloadUrlRequest
	if err := json.Unmarshal([]byte(request.Body), &req); err != nil {
		return errorResponse(400, "Invalid request body", err), nil
	}

	if req.Key == "" {
		return errorResponse(400, "key is required", nil), nil
	}

	if !strings.HasPrefix(req.Key, "uploads/") {
		return errorResponse(403, "Access denied: can only download from uploads/ path", nil), nil
	}

	result, err := presignClient.PresignGetObject(
		ctx,
		&s3.GetObjectInput{
			Bucket: aws.String(cfg.BucketName),
			Key:    aws.String(req.Key),
		},
		func(opts *s3.PresignOptions) {
			opts.Expires = cfg.DownloadExpiration
		},
	)

	if err != nil {
		log.Printf("Failed to generate download presigned URL: %v", err)
		return errorResponse(500, "Failed to generate download URL", err), nil
	}

	presignedURL := result.URL

	response := DownloadUrlResponse{
		DownloadURL: presignedURL,
		ExpiresIn:   int64(cfg.DownloadExpiration.Seconds()),
	}
	body, err := json.Marshal(response)
	if err != nil {
		return errorResponse(500, "Internal error", err), nil
	}
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(body),
		Headers: map[string]string{
			"Content-Type":                "application/json",
			"Access-Control-Allow-Origin": "*",
		},
	}, nil
}

func getFileExtension(filename string) string {
	return strings.TrimPrefix(strings.ToLower(filepath.Ext(filename)), ".")
}

func getAllowedExtensionList(extMap map[string]bool) []string {
	var exts []string
	for ext := range extMap {
		exts = append(exts, ext)
	}
	sort.Strings(exts)
	return exts
}

func errorResponse(statusCode int, message string, err error) events.APIGatewayProxyResponse {
	response := ErrorResponse{
		Error:   message,
		Message: "",
	}
	if err != nil {
		response.Message = err.Error()
	}

	body, _ := json.Marshal(response)
	return events.APIGatewayProxyResponse{
		StatusCode: statusCode,
		Body:       string(body),
		Headers: map[string]string{
			"Content-Type":                "application/json",
			"Access-Control-Allow-Origin": "*",
		},
	}
}

func main() {
	lambda.Start(handler)
}
