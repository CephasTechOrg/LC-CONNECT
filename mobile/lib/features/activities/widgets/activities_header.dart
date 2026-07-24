part of '../screens/activities_screen.dart';

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const AppShellHeader(
      title: 'Activities',
      subtitle: 'Find something happening on campus',
      trailing: NotificationsBellButton(),
    );
  }
}
