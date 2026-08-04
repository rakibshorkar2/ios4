import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import '../models/directory_item.dart';

class HtmlParserService {
  static Future<List<DirectoryItem>> parseApacheDirectoryAsync(
      String htmlContent, String baseUrl) async {
    return compute(_parseInternal, {'html': htmlContent, 'baseUrl': baseUrl});
  }

  static List<DirectoryItem> _parseInternal(Map<String, String> data) {
    return parseApacheDirectory(data['html']!, data['baseUrl']!);
  }

  static List<DirectoryItem> parseApacheDirectory(
      String htmlContent, String baseUrl) {
    final items = <DirectoryItem>[];

    try {
      final document = html_parser.parse(htmlContent);

      // Typical Apache/Nginx open directory structure:
      // <tr><td><a href="filename.ext">filename.ext</a></td><td align="right">Size</td>...</tr>
      // Or just a bunch of <a href="..."> links.

      final anchors = document.querySelectorAll('a');
      for (final a in anchors) {
        final href = a.attributes['href'];
        final text = a.text.trim();

        if (href == null || href.isEmpty) {
          continue;
        }
        if (href.startsWith('?')) {
          continue; // Skip Apache sorting metadata filters
        }
        if (href.startsWith('#')) {
          continue; // Skip anchor tags
        }

        // Skip parent directory links
        final tLower = text.toLowerCase();
        if (href == '../' ||
            href == '/' ||
            href == './' ||
            tLower == 'parent directory' ||
            tLower == 'name' ||
            tLower == 'size' ||
            tLower == 'date' ||
            tLower == 'description' ||
            tLower == 'last modified') {
          continue;
        }

        // Check if it's a directory (usually ends with '/' or has no extension, but standard is '/')
        bool isDir = href.endsWith('/');
        String name = text;
        if (isDir && name.endsWith('/')) {
          name = name.substring(0, name.length - 1);
        }

        // For absolute domains or subdomains acting as directories but lacking a trailing slash in the text
        if (href.startsWith('http') && !isDir && name.isEmpty) {
          // Some listings have raw URLs as links without text
          name = Uri.parse(href).pathSegments.last;
        }

        // Attempt to extract size from adjacent row cells if in a table
        String? sizeStr;
        Element? parent = a.parent;
        if (parent != null && parent.localName == 'td') {
          Element? row = parent.parent;
          if (row != null && row.localName == 'tr') {
            final cells = row.querySelectorAll('td');
            if (cells.length >= 4) {
              sizeStr = cells[3].text.trim();
              if (sizeStr == '-') sizeStr = '';
            }
          }
        }

        // Construct absolute URL and properly encode paths
        String itemUrl;
        try {
          final baseUri = Uri.parse(baseUrl);
          var resolvedUri = baseUri.resolve(href);

          // Ensure directories maintain trailing slashes for correct subsequent navigations
          if (isDir && !resolvedUri.path.endsWith('/')) {
            resolvedUri = resolvedUri.replace(path: '${resolvedUri.path}/');
          }

          itemUrl = resolvedUri.toString();

          // Ignore self-referencing links
          if (itemUrl == baseUrl) continue;
        } catch (_) {
          continue; // Skip mathematically invalid URIs
        }

        items.add(DirectoryItem(
          name: name,
          url: itemUrl,
          type: isDir
              ? DirectoryItemType.directory
              : DirectoryItem.typeFromExtension(name),
          size: sizeStr,
        ));
      }
    } catch (e) {
      // SILENT
    }

    return items;
  }
}
