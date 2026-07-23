package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/request"
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
	Dowlaodurl string `json:"downloadUrl"`
	ExpiresIn  int    `json:"expiresIn"`
}

type DowloadUrlResponse struct {
	key string
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

func handler(ctx context.Context , request events.APIGatewayProxyRequest )(events.APIGatewayProxyRequest,error)  {
	
	log.Printf("Received request: %s %s", request.HTTPMethod, request.Path)

	switch{
		case request.Path == "/health" && request.HTTPMethod =="GET"
		   return  handleHealth(ctx)
		case request.Path == "/upload-url" && request.HTTPMethod =="POST"
		   return  handleUploadUrl(ctx ,request)
		case request.Path == "/dowlaod-url" && request.HTTPMethod =="POST"
		   return  handleDowloadUrl(ctx ,request)
	default:
		return events.APIGatewayProxyRequest{
		   StatusCode: 404
		   Body: `{"error": "Not Found"}`,
		   Headers: map[string]string{
			"Content-Type": "application/json",
		   },
		},nil
	} 
}

func handleHealth(ctx context.Context) (events.APIGatewayProxyRequest,error){
     response:= map[string]interface{}{
		"status": "healthy"
		"service": "presigned-url-generator"
		"timestamp": time.Now().Unix(),
		"bucket": cfg.BucketName
		"region": cfg.Region
		"maxFileSize": cfg.Region
	 }

	 body, err := json.Marshal(response)
	 if err != nil {
		return errorResponse(500, "Internal error", err), nil
	}
	return events.APIGatewayProxyRequest{
		   StatusCode: 200
		   Body: string(body),
		   Headers: map[string]string{
			"Content-Type": "application/json",
		   },
		},nil

}

func main() {

}