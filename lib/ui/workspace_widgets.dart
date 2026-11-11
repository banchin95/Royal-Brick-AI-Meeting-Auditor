import 'package:flutter/material.dart';

const brick = Color(0xFF933D32);
const ink = Color(0xFF302B28);
const muted = Color(0xFF7B7771);
const line = Color(0xFFE8E4DE);
const success = Color(0xFF32684C);

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 20 : 32),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: line),
    ),
    child: child,
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.number,
    required this.title,
    this.subtitle,
  });
  final int number;
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF3EBE7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$number',
          style: const TextStyle(color: brick, fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: const TextStyle(color: muted, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class WorkflowSteps extends StatelessWidget {
  const WorkflowSteps({super.key, required this.current});
  final int current;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < 3; i++) ...[
        if (i != 0)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.chevron_right, size: 16, color: muted),
          ),
        Expanded(
          child: Row(
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: i <= current ? brick : const Color(0xFFE8E4DE),
                child: i < current
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          color: i <= current ? Colors.white : muted,
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  const ['Разговор', 'Роли', 'Отчёт'][i],
                  style: TextStyle(
                    fontSize: MediaQuery.sizeOf(context).width < 600 ? 11 : 12,
                    color: i <= current ? ink : muted,
                    fontWeight: i == current
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}
