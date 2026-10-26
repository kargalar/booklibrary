import 'package:flutter/material.dart';

import '../data/local_identity.dart';
import 'profile_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) =>
      ProfileGate(user: LocalIdentity.instance.currentUser!);
}
