package main

type Config struct {
	BucketName         string
	Region             string
	UploadExpiration   string
	DownloadExpiration string
	MaxFileSize        string
	AllowedExtentions  map[string]bool
}

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

func main() {

}
