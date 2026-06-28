import 'dart:io';

void main() async {
  final urls = [
    'https://images.unsplash.com/photo-1554568218-0f1715e72254?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1542272604-780c82fb2343?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1591369822096-ffd140ec948f?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1595950653106-6c9ebd614d3a?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1572804013309-59a88b7e92f1?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1624378439575-d8705ad7ae80?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1503342217505-b0a15ec3261c?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1584916201218-f4242ceb4809?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1559551408-df726b2b73bc?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1541099649105-f69ad21f3246?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1608256246200-53e635b5b65f?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1552374196-1ab2a1c593e8?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1529374255404-311a2a4f1fd9?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1583496661160-c588c2589f85?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1601004890684-d8cbf643f5f2?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1514989940723-e8e51635b782?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1582142301229-633208552125?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1516257984-b1b4d707412e?auto=format&fit=crop&q=80&w=600&h=600',
    'https://images.unsplash.com/photo-1590874103328-eac38a683ce7?auto=format&fit=crop&q=80&w=600&h=600',
  ];

  final client = HttpClient();
  
  for (var i = 0; i < urls.length; i++) {
    try {
      final request = await client.headUrl(Uri.parse(urls[i]));
      final response = await request.close();
      if (response.statusCode != 200) {
        print('URL ${i + 1} failed: ${response.statusCode} - ${urls[i]}');
      }
    } catch (e) {
      print('URL ${i + 1} error: $e - ${urls[i]}');
    }
  }
  
  client.close();
  print('Done checking');
}
