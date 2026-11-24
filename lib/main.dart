import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'firebase_options.dart';

const _initialEmail = 'leauhyembi@gmail.com';
const _navy = Color(0xFF10243A);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final preferences = await SharedPreferences.getInstance();
  runApp(MessengerApp(preferences: preferences));
}

enum AppTheme { navy, light, dark }

class MessengerApp extends StatefulWidget {
  const MessengerApp({required this.preferences, super.key});

  final SharedPreferences preferences;

  @override
  State<MessengerApp> createState() => _MessengerAppState();
}

class _MessengerAppState extends State<MessengerApp> {
  late AppTheme _theme;

  @override
  void initState() {
    super.initState();
    _theme = AppTheme.values.firstWhere(
      (theme) => theme.name == widget.preferences.getString('appTheme'),
      orElse: () => AppTheme.navy,
    );
  }

  Future<void> _setTheme(AppTheme theme) async {
    await widget.preferences.setString('appTheme', theme.name);
    setState(() => _theme = theme);
  }

  ThemeData _makeTheme(Brightness brightness, Color seed) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ),
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: brightness == Brightness.dark ? null : seed,
        foregroundColor: brightness == Brightness.dark ? null : Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeData = switch (_theme) {
      AppTheme.navy => _makeTheme(Brightness.light, _navy),
      AppTheme.light => _makeTheme(Brightness.light, Colors.blueGrey),
      AppTheme.dark => _makeTheme(Brightness.dark, _navy),
    };

    return MaterialApp(
      title: 'Messagerie',
      theme: themeData,
      home: AuthGate(onThemeChanged: _setTheme, selectedTheme: _theme),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({
    required this.onThemeChanged,
    required this.selectedTheme,
    super.key,
  });

  final ValueChanged<AppTheme> onThemeChanged;
  final AppTheme selectedTheme;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingPage();
        }
        final user = snapshot.data;
        if (user == null) {
          return const SignInPage();
        }
        if (!user.emailVerified) {
          return const VerifyEmailPage();
        }
        return ConversationsPage(
          onThemeChanged: onThemeChanged,
          selectedTheme: selectedTheme,
        );
      },
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController(text: _initialEmail);
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _isRegistering = false;
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      if (_isRegistering) {
        final credential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
        await credential.user!.updateDisplayName(_name.text.trim());
        await FirebaseFirestore.instance
            .collection('users')
            .doc(credential.user!.uid)
            .set({
          'displayName': _name.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        });
        await credential.user!.sendEmailVerification();
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(_authErrorMessage(error));
    } on FirebaseException catch (error) {
      _showMessage('Erreur Firebase : ${error.message ?? error.code}');
    } catch (error) {
      _showMessage('Une erreur inattendue est survenue : $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showMessage('Saisissez d’abord votre adresse e-mail.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showMessage('Si ce compte existe, un lien de réinitialisation a été envoyé.');
    } on FirebaseAuthException catch (error) {
      _showMessage(_authErrorMessage(error));
    } catch (error) {
      _showMessage('Impossible d’envoyer le lien : $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _authErrorMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-email' => 'Adresse e-mail invalide.',
      'user-not-found' || 'wrong-password' || 'invalid-credential' =>
        'Adresse e-mail ou mot de passe incorrect.',
      'email-already-in-use' => 'Cette adresse possède déjà un compte.',
      'weak-password' => 'Choisissez un mot de passe d’au moins 8 caractères.',
      'too-many-requests' => 'Trop de tentatives. Réessayez plus tard.',
      _ => error.message ?? 'Authentification impossible (${error.code}).',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.forum_rounded, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    'Messagerie',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isRegistering
                        ? 'Créez un compte avec une adresse e-mail valide.'
                        : 'Connectez-vous avec votre adresse e-mail.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (_isRegistering) ...[
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                          const InputDecoration(labelText: 'Nom affiché'),
                      validator: (value) {
                        if (_isRegistering &&
                            (value == null || value.trim().isEmpty)) {
                          return 'Saisissez votre nom.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Adresse e-mail',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null ||
                          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                              .hasMatch(value.trim())) {
                        return 'Saisissez une adresse e-mail valide.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    autofillHints: _isRegistering
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Saisissez votre mot de passe.';
                      }
                      if (_isRegistering && value.length < 8) {
                        return 'Utilisez au moins 8 caractères.';
                      }
                      return null;
                    },
                  ),
                  if (!_isRegistering)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _resetPassword,
                        child: const Text('Mot de passe oublié ?'),
                      ),
                    )
                  else
                    const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isRegistering ? 'Créer un compte' : 'Connexion'),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(
                              () => _isRegistering = !_isRegistering,
                            ),
                    child: Text(
                      _isRegistering
                          ? 'J’ai déjà un compte'
                          : 'Créer un nouveau compte',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool _busy = false;

  Future<void> _checkVerification() async {
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.currentUser!.reload();
      if (mounted && FirebaseAuth.instance.currentUser?.emailVerified == true) {
        setState(() {});
      } else {
        _message('Validez le lien reçu par e-mail, puis réessayez.');
      }
    } on FirebaseAuthException catch (error) {
      _message(error.message ?? 'Vérification impossible (${error.code}).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await FirebaseAuth.instance.currentUser!.sendEmailVerification();
      _message('E-mail de vérification envoyé.');
    } on FirebaseAuthException catch (error) {
      _message(error.message ?? 'Envoi impossible (${error.code}).');
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vérifier votre adresse')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Un lien de vérification a été envoyé à '
                  '${FirebaseAuth.instance.currentUser?.email ?? 'votre adresse'}.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _checkVerification,
                  child: const Text('J’ai vérifié mon adresse'),
                ),
                TextButton(
                  onPressed: _resend,
                  child: const Text('Renvoyer le lien'),
                ),
                TextButton(
                  onPressed: FirebaseAuth.instance.signOut,
                  child: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      );
}

class ConversationsPage extends StatelessWidget {
  const ConversationsPage({
    required this.onThemeChanged,
    required this.selectedTheme,
    super.key,
  });

  final ValueChanged<AppTheme> onThemeChanged;
  final AppTheme selectedTheme;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      FirebaseFirestore.instance.collection('conversations');

  Future<void> _startConversation(BuildContext context) async {
    final peerUid = await showDialog<String>(
      context: context,
      builder: (context) => const _StartConversationDialog(),
    );
    if (peerUid == null || !context.mounted) return;

    final user = FirebaseAuth.instance.currentUser!;
    if (peerUid == user.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vous ne pouvez pas discuter avec vous-même.')),
      );
      return;
    }
    final participants = [user.uid, peerUid]..sort();
    final conversationId = participants.join('__');
    try {
      final reference = _conversations.doc(conversationId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists) {
          transaction.set(reference, {
            'participants': participants,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'lastMessage': '',
          });
        }
      });
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatPage(
              conversationId: conversationId,
              peerUid: peerUid,
            ),
          ),
        );
      }
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Impossible de créer la conversation : '
                '${error.message ?? error.code}'),
          ),
        );
      }
    }
  }

  Future<String> _conversationTitle(List<dynamic> participants) async {
    final peerUid = participants
        .whereType<String>()
        .firstWhere((uid) => uid != FirebaseAuth.instance.currentUser!.uid);
    try {
      final profile =
          await FirebaseFirestore.instance.collection('users').doc(peerUid).get();
      final name = profile.data()?['displayName'];
      return name is String && name.isNotEmpty
          ? name
          : 'Utilisateur ${_shortUid(peerUid)}';
    } on FirebaseException {
      return 'Utilisateur ${_shortUid(peerUid)}';
    }
  }

  String _shortUid(String uid) => uid.substring(0, uid.length < 7 ? uid.length : 7);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messagerie'),
        actions: [
          PopupMenuButton<AppTheme>(
            tooltip: 'Choisir le thème',
            initialValue: selectedTheme,
            onSelected: onThemeChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: AppTheme.navy,
                child: Text('Bleu marine'),
              ),
              PopupMenuItem(value: AppTheme.light, child: Text('Blanc')),
              PopupMenuItem(value: AppTheme.dark, child: Text('Noir')),
            ],
            icon: const Icon(Icons.palette_outlined),
          ),
          IconButton(
            tooltip: 'Profil et identifiant',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Votre profil'),
                content: SelectableText(
                  'E-mail : ${FirebaseAuth.instance.currentUser?.email ?? ''}\n\n'
                  'Identifiant à partager :\n$uid',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fermer'),
                  ),
                  TextButton(
                    onPressed: FirebaseAuth.instance.signOut,
                    child: const Text('Déconnexion'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _conversations
            .where('participants', arrayContains: uid)
            .orderBy('updatedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erreur de chargement : ${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final conversations = snapshot.data!.docs;
          if (conversations.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aucune conversation pour le moment.\n'
                  'Créez-en une avec l’identifiant Firebase d’un autre utilisateur.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: conversations.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              final data = conversation.data();
              final participants = data['participants'] as List<dynamic>;
              final peerUid = participants
                  .whereType<String>()
                  .firstWhere((id) => id != uid);
              return FutureBuilder<String>(
                future: _conversationTitle(participants),
                builder: (context, titleSnapshot) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(titleSnapshot.data ?? 'Chargement…'),
                  subtitle: Text(
                    data['lastMessage'] as String? ?? 'Démarrer la conversation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatPage(
                        conversationId: conversation.id,
                        peerUid: peerUid,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startConversation(context),
        tooltip: 'Nouvelle conversation',
        child: const Icon(Icons.add_comment_outlined),
      ),
    );
  }
}

class _StartConversationDialog extends StatefulWidget {
  const _StartConversationDialog();

  @override
  State<_StartConversationDialog> createState() =>
      _StartConversationDialogState();
}

class _StartConversationDialogState extends State<_StartConversationDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nouvelle conversation'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Identifiant Firebase du destinataire',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final uid = _controller.text.trim();
              if (uid.isNotEmpty) Navigator.pop(context, uid);
            },
            child: const Text('Continuer'),
          ),
        ],
      );
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.conversationId,
    required this.peerUid,
    super.key,
  });

  final String conversationId;
  final String peerUid;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _text = TextEditingController();
  final _picker = ImagePicker();
  bool _sending = false;

  CollectionReference<Map<String, dynamic>> get _messages =>
      FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .collection('messages');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    _text.clear();
    await _sendMessage(text: text);
  }

  Future<void> _sendMessage({
    String text = '',
    XFile? media,
    String? mediaType,
  }) async {
    setState(() => _sending = true);
    try {
      final messageRef = _messages.doc();
      String? mediaPath;
      if (media != null && mediaType != null) {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        final extension = media.name.contains('.')
            ? media.name.split('.').last.toLowerCase()
            : (mediaType == 'video' ? 'mp4' : 'jpg');
        mediaPath =
            'conversations/${widget.conversationId}/$uid/${messageRef.id}.$extension';
        final contentType = media.mimeType ??
            (mediaType == 'video' ? 'video/mp4' : 'image/jpeg');
        await FirebaseStorage.instance.ref(mediaPath).putFile(
              File(media.path),
              SettableMetadata(contentType: contentType),
            );
      }
      final batch = FirebaseFirestore.instance.batch();
      batch.set(messageRef, {
        'senderId': FirebaseAuth.instance.currentUser!.uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        if (mediaPath != null) 'mediaPath': mediaPath,
        if (mediaType != null) 'mediaType': mediaType,
      });
      batch.update(
        FirebaseFirestore.instance
            .collection('conversations')
            .doc(widget.conversationId),
        {
          'lastMessage': mediaType == 'image'
              ? 'Photo'
              : mediaType == 'video'
                  ? 'Vidéo'
                  : text,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      await batch.commit();
    } on FirebaseException catch (error) {
      _showError('Envoi impossible : ${error.message ?? error.code}');
    } catch (error) {
      _showError('Envoi impossible : $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _chooseMedia({required bool video}) async {
    try {
      final media = video
          ? await _picker.pickVideo(source: ImageSource.gallery)
          : await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );
      if (media != null) {
        await _sendMessage(media: media, mediaType: video ? 'video' : 'image');
      }
    } catch (error) {
      _showError('Impossible de sélectionner le fichier : $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.peerUid)
        .get()
        .then((snapshot) =>
            snapshot.data()?['displayName'] as String? ?? 'Conversation');

    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<String>(
          future: titleFuture,
          builder: (context, snapshot) =>
              Text(snapshot.data ?? 'Conversation'),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messages
                  .orderBy('createdAt', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Erreur de chargement : ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!.docs;
                if (messages.isEmpty) {
                  return const Center(child: Text('Envoyez le premier message.'));
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => _MessageBubble(
                    data: messages[index].data(),
                    own: messages[index].data()['senderId'] ==
                        FirebaseAuth.instance.currentUser!.uid,
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Envoyer une photo',
                    onPressed:
                        _sending ? null : () => _chooseMedia(video: false),
                    icon: const Icon(Icons.image_outlined),
                  ),
                  IconButton(
                    tooltip: 'Envoyer une vidéo',
                    onPressed:
                        _sending ? null : () => _chooseMedia(video: true),
                    icon: const Icon(Icons.video_library_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Votre message',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onSubmitted: (_) => _sendText(),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Envoyer',
                    onPressed: _sending ? null : _sendText,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.data, required this.own});

  final Map<String, dynamic> data;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final mediaPath = data['mediaPath'] as String?;
    final mediaType = data['mediaType'] as String?;
    final text = data['text'] as String? ?? '';
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: own ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mediaPath != null && mediaType == 'image')
              _SecureImage(path: mediaPath),
            if (mediaPath != null && mediaType == 'video')
              _SecureVideo(path: mediaPath),
            if (text.isNotEmpty) Text(text),
          ],
        ),
      ),
    );
  }
}

class _SecureImage extends StatelessWidget {
  const _SecureImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return _SecureImageLoader(path: path);
  }
}

class _SecureImageLoader extends StatefulWidget {
  const _SecureImageLoader({required this.path});

  final String path;

  @override
  State<_SecureImageLoader> createState() => _SecureImageLoaderState();
}

class _SecureImageLoaderState extends State<_SecureImageLoader> {
  late final Future<Uint8List?> _imageData;

  @override
  void initState() {
    super.initState();
    _imageData =
        FirebaseStorage.instance.ref(widget.path).getData(15 * 1024 * 1024);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _imageData,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Impossible de charger cette image.');
        }
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 160,
            width: 240,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            snapshot.data!,
            width: 240,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Text('Image illisible.'),
          ),
        );
      },
    );
  }
}

class _SecureVideo extends StatefulWidget {
  const _SecureVideo({required this.path});

  final String path;

  @override
  State<_SecureVideo> createState() => _SecureVideoState();
}

class _SecureVideoState extends State<_SecureVideo> {
  VideoPlayerController? _controller;
  String? _error;
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        'private_${widget.path.split('/').last}',
      );
      await FirebaseStorage.instance.ref(widget.path).writeToFile(file);
      _localPath = file.path;
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        await file.delete();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (mounted) setState(() => _error = 'Vidéo indisponible : $error');
    }
  }

  @override
  void dispose() {
    unawaited(_disposeVideo());
    super.dispose();
  }

  Future<void> _disposeVideo() async {
    final controller = _controller;
    final path = _localPath;
    if (controller != null) await controller.dispose();
    if (path == null) return;
    try {
      await File(path).delete();
    } on FileSystemException catch (error) {
      debugPrint('Could not remove temporary video: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) return Text(_error!);
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox(
        height: 160,
        width: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return SizedBox(
      width: 240,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
          IconButton(
            onPressed: () => setState(
              () => controller.value.isPlaying
                  ? controller.pause()
                  : controller.play(),
            ),
            icon: Icon(
              controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
          ),
        ],
      ),
    );
  }
}
