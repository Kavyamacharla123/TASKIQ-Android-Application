import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/task_model.dart';
import '../theme.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text("Not Logged In")));

    return Scaffold(
      appBar: AppBar(title: const Text("Analytics Dashboard")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(uid)
            .collection("tasks")
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final tasks = snapshot.data!.docs.map((d) => TaskModel.fromDocument(d)).toList();
          
          if (tasks.isEmpty) return const Center(child: Text("No tasks for analytics yet."));

          final total = tasks.length;
          final completed = tasks.where((t) => t.completed).length;
          final pending = total - completed;

          final high = tasks.where((t) => t.priority == 'High').length;
          final medium = tasks.where((t) => t.priority == 'Medium').length;
          final low = tasks.where((t) => t.priority == 'Low').length;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                _buildStatCard(context, "Completed", completed, total, Colors.green),
                const SizedBox(height: 20),
                const Text("Task Priority Distribution", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                SizedBox(
                  height: 250,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: [
                        if (high > 0) PieChartSectionData(color: ThemeProvider.getPriorityColor('High'), value: high.toDouble(), title: 'High\n$high', radius: 60, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        if (medium > 0) PieChartSectionData(color: ThemeProvider.getPriorityColor('Medium'), value: medium.toDouble(), title: 'Med\n$medium', radius: 60, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        if (low > 0) PieChartSectionData(color: ThemeProvider.getPriorityColor('Low'), value: low.toDouble(), title: 'Low\n$low', radius: 60, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  child: ListTile(
                    title: const Text("Total Tasks"),
                    trailing: Text("$total", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text("Pending Tasks"),
                    trailing: Text("$pending", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, int current, int total, Color color) {
    double progress = total == 0 ? 0 : current / total;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("$current / $total tasks", style: const TextStyle(color: Colors.grey)),
                Text("${(progress * 100).toStringAsFixed(1)}%", style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress, color: color, backgroundColor: color.withOpacity(0.2)),
          ],
        ),
      ),
    );
  }
}
