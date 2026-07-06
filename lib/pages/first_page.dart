import 'package:flutter/material.dart';

class FirstPage extends StatelessWidget {
  const FirstPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page'),
      ),
      drawer: const Drawer(), // ✅ Drawer belongs here
      body: ListView(          // ✅ use body, not child
        children: const [
          ListTile(
            title: Text('First Page'),
            subtitle: Text('This is the first page.'),
            leading: Icon(Icons.home), // ✅ use leading, not child
          ),
        ],
      ),
    );
  }
}
