

> Add a **"New Download"** feature to the existing **Downloads** tab of my Flutter iOS app without changing the current UI or download architecture.
>
> Requirements:
>
> * Add a **"+"** button (or download icon) in the Downloads app bar.
> * Tapping it opens a modal/bottom sheet with:
>
>   * URL input field
>   * "Paste from Clipboard" button
>   * Optional filename field (auto-filled when possible)
>   * "Download" and "Cancel" buttons
> * Validate that the entered URL is a valid HTTP or HTTPS URL.
> * Before downloading, perform an HTTP HEAD request (or GET if HEAD is not supported) to retrieve:
>
>   * Content-Length
>   * Content-Type
>   * Content-Disposition
>   * Accept-Ranges
> * Automatically determine the filename from `Content-Disposition` or the URL if no filename is provided.
> * Show a confirmation dialog displaying:
>
>   * Filename
>   * File size
>   * File type
>   * Resume support (Yes/No)
> * When the user confirms, create a download task using the app's existing download manager and queue system.
> * The download must use the app's existing SOCKS5 proxy settings if enabled.
> * Support large files and resumable downloads whenever the server supports HTTP Range requests.
> * Handle errors gracefully (invalid URL, network failure, expired links, permission issues, etc.).
> * Follow the existing project architecture, state management, and UI style. Do not rewrite existing download logic—only integrate this new feature cleanly into the current codebase.
>
> The goal is to let users paste any direct HTTP/HTTPS file link (for example, `.mp4`, `.zip`, `.mkv`, `.pdf`, `.iso`, etc.) and download it through the app just like a typical download manager.






> Improve the **New Download** feature in my existing Flutter iOS app. The download functionality already works, but the metadata detection needs to be more reliable and the confirmation dialog should be enhanced.
>
> Requirements:
>
> * Fix file metadata detection so that before downloading the app accurately retrieves:
>
>   * File size (`Content-Length`)
>   * MIME type (`Content-Type`)
>   * Filename (`Content-Disposition`, URL path, or final redirected URL)
>   * Resume support (`Accept-Ranges`)
> * Follow HTTP redirects before reading headers.
> * If the server doesn't support `HEAD`, automatically fall back to a lightweight `GET` request (`Range: bytes=0-0`) to obtain headers.
> * If `Content-Type` is generic (`text/plain` or `application/octet-stream`), infer the correct file type from:
>
>   * the filename extension,
>   * the final URL,
>   * or the response headers.
> * Format file sizes into human-readable units (KB, MB, GB, TB).
> * Show **Unknown** only if the server truly does not provide the information.
> * Display the confirmation dialog only after metadata retrieval is complete, showing a loading indicator while fetching.
>
> **Enhance the confirmation dialog:**
>
> * Add a file icon based on MIME type.
> * Display:
>
>   * Filename
>   * File size
>   * File type
>   * Resume support (Yes/No)
>   * Direct host/domain (e.g. `googleusercontent.com`)
>   * Save location
>   * Proxy status (Enabled/Disabled)
> * Allow the user to edit the filename before starting the download.
> * If metadata retrieval fails, allow downloading anyway with a warning instead of blocking the user.
> * Cache retrieved metadata so reopening the dialog doesn't perform another network request.
>
> The implementation should integrate with the existing download manager and preserve the current UI style and architecture without rewriting the existing download logic.
