import 'dart:io';

void main() async {
  final urls = [
    'https://images.unsplash.com/photo-1541099649105-f69ad21f3246?auto=format&fit=crop&q=80&w=600&h=600', // Already working jeans
    'https://images.unsplash.com/photo-1582552938352-41146845302a?auto=format&fit=crop&q=80&w=600&h=600', // Test jeans
    'https://images.unsplash.com/photo-1520975954732-57dd22299614?auto=format&fit=crop&q=80&w=600&h=600', // Test jacket
    'https://images.unsplash.com/photo-1516762689617-e1cffcef479d?auto=format&fit=crop&q=80&w=600&h=600', // Test clothing
    'https://images.unsplash.com/photo-1525507119028-ed4c629a60a3?auto=format&fit=crop&q=80&w=600&h=600', // Clothing
    'https://images.unsplash.com/photo-1509631179647-0177331693ae?auto=format&fit=crop&q=80&w=600&h=600', // Clothing
    'https://images.unsplash.com/photo-1504198458649-3128b932f49e?auto=format&fit=crop&q=80&w=600&h=600', // Clothing
    'https://images.unsplash.com/photo-1543163521-1bf539c55dd2?auto=format&fit=crop&q=80&w=600&h=600', // Shoes
    'https://images.unsplash.com/photo-1515347619362-e67417e2311b?auto=format&fit=crop&q=80&w=600&h=600',
  ];

  final client = HttpClient();
  
  for (var i = 0; i < urls.length; i++) {
    try {
      final request = await client.headUrl(Uri.parse(urls[i]));
      final response = await request.close();
      if (response.statusCode != 200) {
        print('URL ${i + 1} failed: ${response.statusCode} - ${urls[i]}');
      } else {
        print('URL ${i + 1} OK');
      }
    } catch (e) {
      print('URL ${i + 1} error: $e - ${urls[i]}');
    }
  }
  
  client.close();
  print('Done checking');
}
