import 'package:flutter/material.dart';

void main() {
  runApp(const RoyalBrickApp());
}

class RoyalBrickApp extends StatelessWidget {
  const RoyalBrickApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Royal Brick — Аудитор встреч',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF933D32)),
        scaffoldBackgroundColor: const Color(0xFFF7F5F2),
      ),
      home: const StartPage(),
    );
  }
}

class StartPage extends StatefulWidget {
  const StartPage({super.key});

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    'ROYAL BRICK',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Text(
                    'Аудитор встреч',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Рабочее пространство для анализа переговоров '
                    'менеджеров с клиентами.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    color: Colors.white,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Chip(
                            avatar: Icon(Icons.check_circle_outline, size: 18),
                            label: Text('Flutter Web запущен'),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Первый шаг готов',
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Это стартовый экран MVP. Следующий этап — '
                            'интерфейс и анализ демонстрационного текста '
                            'по спецификации Royal Brick.',
                            style: TextStyle(height: 1.6),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => setState(() => _checked = true),
                            icon: Icon(
                              _checked ? Icons.done : Icons.touch_app_outlined,
                            ),
                            label: const Text('Проверить приложение'),
                          ),
                          if (_checked) ...[
                            const SizedBox(height: 16),
                            Semantics(
                              liveRegion: true,
                              child: const Text(
                                'Интерфейс отвечает. Можно переходить '
                                'к следующему этапу.',
                                style: TextStyle(color: Color(0xFF276447)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Этап 1 из 6 · Локальный прототип',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
