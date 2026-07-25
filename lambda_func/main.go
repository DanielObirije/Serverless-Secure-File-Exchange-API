package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"
	"time"
	"uuid"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/s3"
)

type Config struct {
	BucketName         string
	Region             string
	UploadExpiration   int64
	DownloadExpiration int64
	MaxFileSize        int64
	AllowedExtentions  map[string]bool
}

var (
	cfg      *Config
	s3Client *s3.S3
)

type UploadUrlRequest struct {
	Filename string `json:"filename"`
}

type UploadUrlRespond struct {
	UploadUrl string `json:"uploadUrl"`
	key       string
	ExpiresIn int64 `json:"expiresIn"`
}

type DowloadUrlRequest struct {
	Key string `json:"key"`
}

type DowloadUrlResponse struct {
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
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-1"
	}

	cfg = &Config{
		BucketName:         bucketName,
		Region:             region,
		UploadExpiration:   900,
		DownloadExpiration: 300,
		MaxFileSize:        10 * 1024 * 1024,
		AllowedExtentions: map[string]bool{
			"pdf":  true,
			"png":  true,
			"jpg":  true,
			"jpeg": true,
			"docx": true,
		},
	}
	sess := session.Must(session.NewSession(&aws.Config{
		Region: aws.String(region),
	}))
	s3Client = s3.New(sess)
}

func handler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {

	log.Printf("Received request: %s %s", request.HTTPMethod, request.Path)

	switch {
	case request.Path == "/health" && request.HTTPMethod == "GET":
		return handleHealth(ctx)
	case request.Path == "/upload-url" && request.HTTPMethod == "POST":
		return handleUploadUrl(ctx, request)
	case request.Path == "/dowlaod-url" && request.HTTPMethod == "POST":
		return handleDowloadUrl(ctx, request)
	default:
		return events.APIGatewayProxyResponse{
			StatusCode: 404,
			Body:       `{"error": "Not Found"}`,
			Headers: map[string]string{
				"Content-Type": "application/json",
			},
		}, nil
	}
}

func handleHealth(ctx context.Context) (events.APIGatewayProxyResponse, error) {
	response := map[string]interface{}{
		"status":      "healthy",
		"service":     "presigned-url-generator",
		"timestamp":   time.Now().Unix(),
		"bucket":      cfg.BucketName,
		"region":      cfg.Region,
		"maxFileSize": cfg.Region,
	}

	body, err := json.Marshal(response)
	if err != nil {
		return errorResponse(500, "Internal error", err), nil
	}
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(body),
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
	}, nil

}

func handleUploadUrl(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	var req UploadUrlRequest
	if err := json.Unmarshal([]byte(request.Body), &req); err != nil {
		return ErrorResponse(400, "Invalid request body", err), nil
	}

	if req.Filename == "" {
		return ErrorResponse(400, "filename is required", nil), nil
	}

	ext := getFileExtention(req.Filename)
	if ext == "" {
		return errorResponse(400, "File must have an extension", nil), nil
	}

	if !cfg.AllowedExtensions[ext] {
		return errorResponse(400, fmt.Sprintf("File extension .%s not allowed. Allowed: %v", ext, getAllowedExtensionsList(cfg.AllowedExtensions)), nil), nil
	}

	fileID := uuid.New().String()
	key := fmt.Sprintf("uploads/%s/%s", fileID, req.Filename)

	reqParams := &s3.PutObjectInput{
		Bucket: aws.String(cfg.BucketName),
		Key:    aws.String(key),
	}

	presignedURL, err := s3Client.PresignRequest(reqParams, cfg.UploadExpiration)

	if err != nil {
		log.Printf("Failed to generate presigned URL: %v", err)
		return errorResponse(500, "Failed to generate upload URL", err), nil
	}

	response := UploadUrlRespond{
		UploadUrl: presignedURL,
		key:       key,
		ExpiresIn: cfg.UploadExpiration,
	}

	body, err := json.Marshal(response)
	if err != nil {
		return errorResponse(500, "Internal error", err), nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(body),
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
	}, nil
}

func handleDowloadUrl(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	var req DowloadUrlRequest
	if err := json.Unmarshal([]byte(request.Body), &req); err != nil {
		return errorResponse(400, "Invalid request body", err), nil
	}

	if req.Key == "" {
		return errorResponse(400, "key is required", nil), nil
	}

	if !strings.HasPrefix(req.Key, "uploads/") {
		return errorResponse(403, "Access denied: can only download from uploads/ path", nil), nil
	}
	reqParams := &s3.GetObjectAclInput{
		Bucket: aws.String(&cfg.BucketName),
		Key:    string(req.Key),
	}

	presignedURL, err := s3Client.PresignRequest(reqParams, cfg.DownloadExpiration)
	if err != nil {
		log.Printf("Failed to generate download presigned URL: %v", err)
		return errorResponse(500, "Failed to generate download URL", err), nil
	}

	response := DowloadUrlResponse{
		DownloadURL: presignedURL,
		ExpiresIn:   cfg.DownloadExpiration,
	}
	body, err := json.Marshal(response)
	if err != nil {
		return errorResponse(500, "Internal error", err), nil
	}
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(body),
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
	}, nil
}

func getFileExtention(filename string) string {
	parts := strings.Split(filename, ".")
	if len(parts) < 2 {
		return ""
	}
	return strings.ToLower(parts[len(parts)-1])
}

func getAllowedExtentionList(extMap map[string]bool) []string {
	var exts []string
	for ext := range extMap {
		exts = append(exts, ext)
	}
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
			"Content-Type": "application/json",
		},
	}
}

func main() {
	lambda.Start(handler)
}
