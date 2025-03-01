import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:photoshare/main.dart';
import 'package:photoshare/screens/session_view.dart';

class AppRouter {
final router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const PhotoShareApp(),
    ),
   GoRoute(
      path: '/session/:sessionId',
      builder: (context, state) {
        final sessionId = state.pathParameters['sessionId']!;
        print('Go Router navigating to session: $sessionId');
        return SessionView(sessionId: sessionId);
      },
    ),
    GoRoute(
      path: '/api/v1/session/:sessionId/auth',
      builder: (context, state) {
        final sessionId = state.pathParameters['sessionId']!;
        return SessionView(sessionId: sessionId);
      },
    ),

  ],
    debugLogDiagnostics: true,
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('Page Not Found')),
    body: Center(
      child: Text('No route found for ${state.uri.path}'),
    ),
  ),



  );
}
