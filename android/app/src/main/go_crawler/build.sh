#!/bin/bash
# Requisites: Android NDK and Go installed
# Set CC to Android NDK clang

echo "Building Go crawler for Android ARM64..."
GOOS=android GOARCH=arm64 CGO_ENABLED=1 go build -buildmode=c-shared -o ../jniLibs/arm64-v8a/libcrawler.so crawler.go

echo "Building Go crawler for Android ARM32..."
GOOS=android GOARCH=arm CGO_ENABLED=1 go build -buildmode=c-shared -o ../jniLibs/armeabi-v7a/libcrawler.so crawler.go

echo "Building Go crawler for Android x86_64..."
GOOS=android GOARCH=amd64 CGO_ENABLED=1 go build -buildmode=c-shared -o ../jniLibs/x86_64/libcrawler.so crawler.go

echo "Done."
