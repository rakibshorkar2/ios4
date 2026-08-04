package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"unsafe"

	"golang.org/x/net/html"
	"golang.org/x/net/proxy"
)

// DirectoryItem mirrors the Dart structure
type DirectoryItem struct {
	Name        string `json:"name"`
	URL         string `json:"url"`
	Type        string `json:"type"`
	Size        string `json:"size"`
	IsDirectory bool   `json:"isDirectory"`
}

//export DeepCrawl
func DeepCrawl(targetUrl *C.char, proxyUri *C.char) *C.char {
	goTargetUrl := C.GoString(targetUrl)
	goProxyUri := C.GoString(proxyUri)

	var transport *http.Transport

	// Set up SOCKS5 Proxy if provided
	if goProxyUri != "" {
		pUrl, err := url.Parse(goProxyUri)
		if err == nil {
			dialer, err := proxy.FromURL(pUrl, proxy.Direct)
			if err == nil {
				transport = &http.Transport{
					Dial: dialer.Dial,
				}
			}
		}
	}

	client := &http.Client{
		Transport: transport,
	}

	resp, err := client.Get(goTargetUrl)
	if err != nil {
		return stringToCString(fmt.Sprintf(`{"error": "%v"}`, err))
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return stringToCString(fmt.Sprintf(`{"error": "Status code %d"}`, resp.StatusCode))
	}

	items, err := parseHtml(resp.Body, goTargetUrl)
	if err != nil {
		return stringToCString(fmt.Sprintf(`{"error": "Parsing error: %v"}`, err))
	}

	jsonBytes, err := json.Marshal(items)
	if err != nil {
		return stringToCString(`{"error": "JSON error"}`)
	}

	return stringToCString(string(jsonBytes))
}

func parseHtml(r io.Reader, baseUrl string) ([]DirectoryItem, error) {
	doc, err := html.Parse(r)
	if err != nil {
		return nil, err
	}

	var items []DirectoryItem
	var f func(*html.Node)
	f = func(n *html.Node) {
		if n.Type == html.ElementNode && n.Data == "a" {
			for _, a := range n.Attr {
				if a.Key == "href" {
					href := a.Val
					text := getText(n)

					if href == "../" || strings.ToLower(text) == "parent directory" || text == "Name" || text == "Size" || text == "Date" {
						continue
					}

					if href == "" {
						continue
					}

					isDir := strings.HasSuffix(href, "/")
					name := text
					if isDir && strings.HasSuffix(name, "/") {
						name = name[:len(name)-1]
					}

					itemUrl := href
					if !strings.HasPrefix(href, "http") {
						base := baseUrl
						if !strings.HasSuffix(base, "/") {
							base += "/"
						}
						itemUrl = base + href
					}

					// Basic implementation - omits complex size extraction for brevity in this BFS example
					itemType := "file"
					if isDir {
						itemType = "directory"
					}

					items = append(items, DirectoryItem{
						Name:        name,
						URL:         itemUrl,
						Type:        itemType,
						Size:        "",
						IsDirectory: isDir,
					})
				}
			}
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			f(c)
		}
	}
	f(doc)

	// Ensure we never return nil items array
	if items == nil {
		items = make([]DirectoryItem, 0)
	}
	
	return items, nil
}

func getText(n *html.Node) string {
	if n.Type == html.TextNode {
		return n.Data
	}
	var b strings.Builder
	for c := n.FirstChild; c != nil; c = c.NextSibling {
		b.WriteString(getText(c))
	}
	return strings.TrimSpace(b.String())
}

// Helper to convert Go string to C string properly
func stringToCString(s string) *C.char {
	return C.CString(s)
}

//export FreeCString
func FreeCString(ptr *C.char) {
	C.free(unsafe.Pointer(ptr))
}

func main() {
	// Required for buildmode=c-shared
}
