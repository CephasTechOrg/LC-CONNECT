part of '../screens/home_screen.dart';

class _Header extends StatelessWidget {
  final String greeting;
  const _Header({required this.greeting});

  @override
  Widget build(BuildContext context) {
    return AppShellHeader(
      title: greeting,
      subtitle: 'Livingstone College',
      showBottomBorder: false,
      trailing: const ConnectionsBellButton(),
    );
  }
}
