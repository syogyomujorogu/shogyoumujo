// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'camera_screen.dart';
import 'steps_screen.dart';
import 'mercy_request_screen.dart';
import 'profile_screen.dart';

final supabase = Supabase.instance.client;

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? userData;
  List<Map<String, dynamic>> meals = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadMeals();
    _subscribeToChanges();
  }

  Future<void> _loadUserData() async {
    final userId = supabase.auth.currentUser!.id;

    final response = await supabase
        .from('users')
        .select()
        .eq('user_id', userId)
        .single();

    setState(() {
      userData = response;
      isLoading = false;
    });
  }

  Future<void> _loadMeals() async {
    final userId = supabase.auth.currentUser!.id;

    final response = await supabase
        .from('meals')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(5);

    setState(() {
      meals = List<Map<String, dynamic>>.from(response);
    });
  }

  void _subscribeToChanges() {
    final userId = supabase.auth.currentUser!.id;

    supabase
        .channel('user_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _loadUserData();
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || userData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDegraded = userData?['is_degraded'] ?? false;
    final degradeLevel = (userData?['degrade_level'] ?? 0) as int;
    final currentCalories = userData?['current_calories'] ?? 0;
    final currentSteps = userData?['current_steps'] ?? 0;
    final photoURL = isDegraded
        ? (userData?['degraded_photo_url'] ?? userData?['photo_url'])
        : userData?['photo_url'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('諸行無常ログ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadUserData();
          await _loadMeals();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // プロフィールカード
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundImage: photoURL != null && photoURL != ''
                            ? NetworkImage(photoURL)
                            : null,
                        child: photoURL == null || photoURL == ''
                            ? const Icon(Icons.person, size: 60)
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        userData?['display_name'] ?? 'ユーザー',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (isDegraded)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '⚠️ 劣化レベル: $degradeLevel / 9',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '✨ 完全な状態 (レベル 0)',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            '今日のカロリー',
                            '$currentCalories kcal',
                            Icons.local_fire_department,
                            Colors.orange,
                          ),
                          _buildStatItem(
                            '今日の歩数',
                            '$currentSteps 歩',
                            Icons.directions_walk,
                            Colors.blue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // メインアクションボタン
              _buildActionButton(
                context,
                '食事を撮影',
                Icons.camera_alt,
                Colors.orange,
                () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CameraScreen(),
                    ),
                  );
                  await _loadUserData();
                  await _loadMeals();
                },
              ),
              const SizedBox(height: 12),
              _buildActionButton(
                context,
                '歩数を記録',
                Icons.directions_walk,
                Colors.blue,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StepsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              if (isDegraded)
                _buildActionButton(
                  context,
                  '慈悲を求める',
                  Icons.favorite,
                  Colors.red,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MercyRequestScreen(),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 24),

              // 今日の食事履歴
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '最近の食事',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildMealHistory(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 28),
      label: Text(
        label,
        style: const TextStyle(fontSize: 18),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 60),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildMealHistory() {
    if (meals.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text(
            'まだ食事の記録がありません',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: meals.map((meal) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                meal['image_url'],
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
            title: Text(meal['description'] ?? '食事'),
            subtitle: Text('${meal['calories']} kcal'),
            trailing: Icon(
              meal['is_healthy'] ? Icons.check_circle : Icons.warning,
              color: meal['is_healthy'] ? Colors.green : Colors.red,
            ),
          ),
        );
      }).toList(),
    );
  }
}
