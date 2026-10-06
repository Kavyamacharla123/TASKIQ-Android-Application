import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';

import 'notification_service.dart';
import 'theme.dart';
import 'models/task_model.dart';
import 'screens/login_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/calendar_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.init();
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const SmartTodoApp(),
    ),
  );
}

class SmartTodoApp extends StatelessWidget {
  const SmartTodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: "TaskIQ",
          themeMode: themeProvider.themeMode,
          theme: ThemeProvider.lightTheme,
          darkTheme: ThemeProvider.darkTheme,
          home: const SplashScreen(),
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthGate()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF6C63FF),
      body: Center(
        child: Image(image: AssetImage("assets/logo.jpg"), width: 120),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LoginScreen();
        return const HomeScreen();
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedTab = 0;
  late stt.SpeechToText _speech;
  bool isListening = false;
  String searchQuery = "";
  StreamSubscription<Position>? _positionStream;
  Set<String> alertedTasks = {};
  
  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initLocationTracking();
  }

  Future<void> _initLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    );
    
    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) async {
       if (FirebaseAuth.instance.currentUser == null) return;
       final uid = FirebaseAuth.instance.currentUser!.uid;
       final snap = await FirebaseFirestore.instance.collection("users").doc(uid).collection("tasks").where('completed', isEqualTo: false).get();
       
       for(var doc in snap.docs) {
          final task = TaskModel.fromDocument(doc);
          if (task.lat != null && task.lng != null && !alertedTasks.contains(task.id)) {
             double distance = Geolocator.distanceBetween(position.latitude, position.longitude, task.lat!, task.lng!);
             if (distance < 200) { // Notify if within 200 meters
                await NotificationService.showInstantNotification(id: task.id.hashCode ^ 1234, title: "📍 Location Reminder: ${task.title}", body: "You are near: ${task.location ?? 'a saved task location'}!");
                alertedTasks.add(task.id);
             }
          }
       }
    });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  List<TaskModel> filterTasks(List<TaskModel> tasks) {
    var filtered = tasks.where((t) => t.title.toLowerCase().contains(searchQuery.toLowerCase())).toList();
    if (selectedTab == 1) return filtered.where((t) => t.completed).toList();
    if (selectedTab == 2) return filtered.where((t) => !t.completed).toList();
    return filtered;
  }

  Future<void> startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => isListening = true);
      _speech.listen(onResult: (result) async {
        if (result.finalResult && result.recognizedWords.isNotEmpty) {
          final uid = FirebaseAuth.instance.currentUser!.uid;
          final predictedPriority = SmartPredictor.predictPriority(result.recognizedWords);
          final predictedCategory = SmartPredictor.predictCategory(result.recognizedWords);
          
          await FirebaseFirestore.instance.collection("users").doc(uid).collection("tasks").add(
            TaskModel(
              id: '',
              title: result.recognizedWords,
              priority: predictedPriority,
              completed: false,
              createdAt: DateTime.now(),
              category: predictedCategory,
              orderIndex: DateTime.now().millisecondsSinceEpoch.toDouble(),
            ).toMap()
          );
          
          setState(() => isListening = false);
        }
      });
    }
  }

  void _undoDeleteTask(TaskModel backup, String docId, String uid) {
    FirebaseFirestore.instance.collection("users").doc(uid).collection("tasks").doc(docId).set(backup.toMap());
    if (backup.dueTime != null && backup.dueTime!.isAfter(DateTime.now()) && !backup.completed) {
      NotificationService.scheduleNotification(id: docId.hashCode, title: "Task Reminder: ${backup.title}", body: backup.notes ?? "Task is due now!", scheduledTime: backup.dueTime!);
    }
  }

  void _showProfileBottomSheet(BuildContext context) {
    showModalBottomSheet(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(FirebaseAuth.instance.currentUser?.email ?? FirebaseAuth.instance.currentUser?.phoneNumber ?? "", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                return SwitchListTile(
                  title: const Text("Dark Mode"),
                  value: themeProvider.isDarkMode,
                  onChanged: (val) => themeProvider.toggleTheme(val),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.analytics),
              title: const Text("Analytics Dashboard"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text("Calendar View"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen()));
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              icon: const Icon(Icons.logout),
              label: const Text("Logout"),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("TaskIQ ✨", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.account_circle, size: 30), onPressed: () => _showProfileBottomSheet(context)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search tasks...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
              onChanged: (val) => setState(() => searchQuery = val),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection("users").doc(uid).collection("tasks").orderBy("orderIndex").snapshots(),
        builder: (context, snap) {
           if (!snap.hasData) return const Center(child: CircularProgressIndicator());
           
           final allTasksRaw = snap.data!.docs.map((d) => TaskModel.fromDocument(d)).toList();
           final tasks = filterTasks(allTasksRaw);
           
           final totalTasks = allTasksRaw.length;
           final compTasks = allTasksRaw.where((t) => t.completed).length;
           final progress = totalTasks > 0 ? compTasks / totalTasks : 0.0;

           return Column(
             children: [
               if (totalTasks > 0)
                 Padding(
                   padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Text("Daily Progress: ${(progress * 100).toStringAsFixed(0)}%"),
                       const SizedBox(height: 5),
                       LinearProgressIndicator(value: progress, borderRadius: BorderRadius.circular(10), minHeight: 8),
                     ],
                   ),
                 ),
               Expanded(
                 child: tasks.isEmpty
                     ? const Center(child: Text("No tasks found! Try adding one.", style: TextStyle(fontSize: 16, color: Colors.grey)))
                     : ReorderableListView.builder(
                         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                         itemCount: tasks.length,
                         onReorder: (oldIndex, newIndex) async {
                           if (searchQuery.isNotEmpty || selectedTab != 0) return; // Only allow reorder on default view
                           if (oldIndex < newIndex) newIndex -= 1;
                           final item = tasks.removeAt(oldIndex);
                           tasks.insert(newIndex, item);
                           
                           final batch = FirebaseFirestore.instance.batch();
                           for (int i = 0; i < tasks.length; i++) {
                             final ref = FirebaseFirestore.instance.collection("users").doc(uid).collection("tasks").doc(tasks[i].id);
                             batch.update(ref, {'orderIndex': i.toDouble()});
                           }
                           await batch.commit();
                         },
                         itemBuilder: (context, index) {
                           final task = tasks[index];
                           return Dismissible(
                             key: Key(task.id),
                             background: _buildSwipeBackground(Colors.green, Icons.check, Alignment.centerLeft),
                             secondaryBackground: _buildSwipeBackground(Colors.red, Icons.delete, Alignment.centerRight),
                             confirmDismiss: (direction) async {
                               if (direction == DismissDirection.endToStart) { // Delete
                                 final backup = task;
                                 await FirebaseFirestore.instance.collection("users").doc(uid).collection("tasks").doc(task.id).delete();
                                 await NotificationService.cancelNotification(task.id.hashCode);
                                 if (context.mounted) {
                                   ScaffoldMessenger.of(context).showSnackBar(
                                     SnackBar(
                                       content: const Text("Task deleted"),
                                       action: SnackBarAction(label: "UNDO", onPressed: () => _undoDeleteTask(backup, task.id, uid)),
                                     )
                                   );
                                 }
                                 return true;
                               } else { // Complete
                                 await FirebaseFirestore.instance.collection("users").doc(uid).collection("tasks").doc(task.id).update({'completed': true});
                                 await NotificationService.cancelNotification(task.id.hashCode);
                                 return false;
                               }
                             },
                             child: Card(
                               elevation: 2,
                               margin: const EdgeInsets.only(bottom: 12),
                               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                               child: ListTile(
                                 onTap: () => showDialog(context: context, builder: (_) => AddTaskDialog(existingTask: task)),
                                 leading: CircleAvatar(backgroundColor: ThemeProvider.getPriorityColor(task.priority), child: Text(task.priority[0])),
                                 title: Text(task.title, style: TextStyle(decoration: task.completed ? TextDecoration.lineThrough : null, fontWeight: FontWeight.bold)),
                                 subtitle: Column(
                                   crossAxisAlignment: CrossAxisAlignment.start,
                                   children: [
                                     Text("${task.category} • ${task.dueTime != null ? DateFormat('MMM d, hh:mm a').format(task.dueTime!) : 'No due date'}"),
                                     if (task.location != null) Text("📍 ${task.location}", style: const TextStyle(fontSize: 12, color: Colors.blue)),
                                     if (task.notes != null) Text("📝 ${task.notes}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                     if (task.attachmentUrl != null) const Text("📎 Attachment Included", style: TextStyle(fontSize: 12, color: Colors.orange)),
                                   ]
                                 ),
                                 trailing: ReorderableDragStartListener(
                                   index: index,
                                   child: Checkbox(
                                     value: task.completed,
                                     shape: const CircleBorder(),
                                     onChanged: (v) async {
                                       await FirebaseFirestore.instance.collection("users").doc(uid).collection("tasks").doc(task.id).update({'completed': v});
                                       if (v == true) {
                                         await NotificationService.cancelNotification(task.id.hashCode);
                                       } else if (task.dueTime != null && task.dueTime!.isAfter(DateTime.now())) {
                                         await NotificationService.scheduleNotification(id: task.id.hashCode, title: "Task Reminder: ${task.title}", body: task.notes ?? "Task is due now!", scheduledTime: task.dueTime!);
                                       }
                                     },
                                   ),
                                 ),
                               ),
                             ),
                           );
                         },
                       ),
               ),
             ],
           );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (i) => setState(() => selectedTab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list), label: "All"),
          NavigationDestination(icon: Icon(Icons.done), label: "Completed"),
          NavigationDestination(icon: Icon(Icons.schedule), label: "Pending"),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "mic",
            backgroundColor: isListening ? Colors.redAccent : null,
            onPressed: startListening,
            child: Icon(isListening ? Icons.mic : Icons.mic_none),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: "add",
            icon: const Icon(Icons.add),
            label: const Text("Add Task"),
            onPressed: () => showDialog(context: context, builder: (_) => const AddTaskDialog()),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeBackground(Color color, IconData icon, Alignment alignment) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
      child: Icon(icon, color: Colors.white, size: 30),
    );
  }
}

class SmartPredictor {
  static String predictPriority(String text) {
    final t = text.toLowerCase();
    if (t.contains("urgent") || t.contains("exam") || t.contains("meeting") || t.contains("deadline")) return "High";
    if (t.contains("hobby") || t.contains("game") || t.contains("watch")) return "Low";
    return "Medium";
  }
  
  static String predictCategory(String text) {
    final t = text.toLowerCase();
    if (t.contains("study") || t.contains("read") || t.contains("book")) return "Study";
    if (t.contains("project") || t.contains("code") || t.contains("work")) return "Work";
    return "Personal";
  }
  
  static DateTime? suggestDate(String text) {
    if (text.toLowerCase().contains("tomorrow")) return DateTime.now().add(const Duration(days: 1));
    if (text.toLowerCase().contains("next week")) return DateTime.now().add(const Duration(days: 7));
    return null;
  }
}

class AddTaskDialog extends StatefulWidget {
  final TaskModel? existingTask;
  const AddTaskDialog({super.key, this.existingTask});

  @override
  State<AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<AddTaskDialog> {
  final titleController = TextEditingController();
  final notesController = TextEditingController();
  final locationController = TextEditingController();
  String priority = "Medium";
  String category = "Personal";
  DateTime? selectedDate;
  File? _imageFile;
  String? existingAttachmentUrl;
  bool _isUploading = false;
  double? lat;
  double? lng;
  bool _isLocating = false;
  
  final List<String> aiSuggestions = [
    "Study for 2 hours", "Buy groceries", "Complete project report", "Morning Workout"
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existingTask != null) {
      titleController.text = widget.existingTask!.title;
      notesController.text = widget.existingTask!.notes ?? "";
      locationController.text = widget.existingTask!.location ?? "";
      priority = widget.existingTask!.priority;
      category = widget.existingTask!.category;
      selectedDate = widget.existingTask!.dueTime;
      existingAttachmentUrl = widget.existingTask!.attachmentUrl;
      lat = widget.existingTask!.lat;
      lng = widget.existingTask!.lng;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return AlertDialog(
      title: Text(widget.existingTask == null ? "Smart Add Task ✨" : "Edit Task"),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.existingTask == null && titleController.text.isEmpty) ...[
              const Text("AI Suggestions:", style: TextStyle(fontSize: 12, color: Colors.grey)),
              Wrap(
                spacing: 5,
                children: aiSuggestions.map((s) => ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 11)),
                  onPressed: () {
                    setState(() {
                      titleController.text = s;
                      priority = SmartPredictor.predictPriority(s);
                      category = SmartPredictor.predictCategory(s);
                    });
                  },
                )).toList(),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: "Task Title (e.g. Urgent meeting)"),
              onChanged: (v) {
                setState(() {
                  priority = SmartPredictor.predictPriority(v);
                  category = SmartPredictor.predictCategory(v);
                  if (SmartPredictor.suggestDate(v) != null) selectedDate = SmartPredictor.suggestDate(v);
                });
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: priority,
              items: ["High", "Medium", "Low"].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => setState(() => priority = v!),
              decoration: const InputDecoration(labelText: "Predicted Priority"),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: category,
              items: ["Work", "Study", "Personal"].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => setState(() => category = v!),
              decoration: const InputDecoration(labelText: "Predicted Category"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(labelText: "Description / Notes", prefixIcon: Icon(Icons.notes)),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: locationController,
              decoration: InputDecoration(
                labelText: "Location Reminder (e.g. Near Store)", 
                prefixIcon: const Icon(Icons.location_on),
                suffixIcon: IconButton(
                  icon: _isLocating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location, color: Colors.blue),
                  onPressed: () async {
                    setState(() => _isLocating = true);
                    try {
                      LocationPermission perm = await Geolocator.checkPermission();
                      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
                      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
                        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
                        setState(() {
                          lat = pos.latitude;
                          lng = pos.longitude;
                          if (locationController.text.isEmpty) locationController.text = "Current Location";
                        });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location pinned! You will be notified when near here.")));
                      }
                    } catch (e) {}
                    setState(() => _isLocating = false);
                  },
                )
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.schedule),
                    label: Text(selectedDate == null ? "Schedule Date" : DateFormat("MMM d, hh:mm a").format(selectedDate!)),
                    onPressed: () async {
                      final date = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(2100), initialDate: selectedDate ?? DateTime.now());
                      if (date == null) return;
                      final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                      if (time == null) return;
                      setState(() => selectedDate = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.image),
                  tooltip: "Attach Image",
                  onPressed: () async {
                    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                    if (picked != null) {
                      setState(() => _imageFile = File(picked.path));
                    }
                  },
                )
              ],
            ),
            if (_imageFile != null) ...[
              const Padding(padding: EdgeInsets.only(top:8.0), child: Text("📎 Selected Image", style: TextStyle(color: Colors.green))),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(_imageFile!, height: 150, width: double.infinity, fit: BoxFit.cover)),
            ],
            if (existingAttachmentUrl != null && _imageFile == null) ...[
              const Padding(padding: EdgeInsets.only(top:8.0), child: Text("📎 Attached Image", style: TextStyle(color: Colors.orange))),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(existingAttachmentUrl!, height: 150, width: double.infinity, fit: BoxFit.cover)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
        ElevatedButton(
          onPressed: _isUploading ? null : () async {
            if (titleController.text.isEmpty) return;
            setState(() => _isUploading = true);


            String? finalUrl = existingAttachmentUrl;
            try {
              if (_imageFile != null) {
                final ref = FirebaseStorage.instance.ref().child('task_images/${DateTime.now().millisecondsSinceEpoch}.jpg');
                await ref.putFile(_imageFile!);
                finalUrl = await ref.getDownloadURL();
              }
            } catch (e) {
              // ignore storage error safely
            }
            
            final taskData = TaskModel(
              id: widget.existingTask?.id ?? '',
              title: titleController.text,
              priority: priority,
              completed: widget.existingTask?.completed ?? false,
              createdAt: widget.existingTask?.createdAt ?? DateTime.now(),
              dueTime: selectedDate,
              category: category,
              notes: notesController.text.isNotEmpty ? notesController.text : null,
              location: locationController.text.isNotEmpty ? locationController.text : null,
              lat: lat,
              lng: lng,
              attachmentUrl: finalUrl,
              orderIndex: widget.existingTask?.orderIndex ?? DateTime.now().millisecondsSinceEpoch.toDouble(),
            ).toMap();

            if (widget.existingTask == null) {
              final docRef = await FirebaseFirestore.instance.collection("users").doc(uid).collection("tasks").add(taskData);
              if (selectedDate != null && selectedDate!.isAfter(DateTime.now())) {
                await NotificationService.scheduleNotification(
                  id: docRef.id.hashCode,
                  title: "Task Reminder: ${titleController.text}",
                  body: notesController.text.isNotEmpty ? notesController.text : "Your task is due now!",
                  scheduledTime: selectedDate!,
                );
              }
            } else {
              await FirebaseFirestore.instance.collection("users").doc(uid).collection("tasks").doc(widget.existingTask!.id).update(taskData);
              if (selectedDate != null && selectedDate!.isAfter(DateTime.now()) && !(widget.existingTask?.completed ?? false)) {
                await NotificationService.scheduleNotification(
                  id: widget.existingTask!.id.hashCode,
                  title: "Task Reminder: ${titleController.text}",
                  body: notesController.text.isNotEmpty ? notesController.text : "Your task is due now!",
                  scheduledTime: selectedDate!,
                );
              } else {
                await NotificationService.cancelNotification(widget.existingTask!.id.hashCode);
              }
            }
            
            if (context.mounted) {
              setState(() => _isUploading = false);
              Navigator.pop(context);
            }
          },
          child: _isUploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.existingTask == null ? "Add Smart Task" : "Update"),
        ),
      ],
    );
  }
}
