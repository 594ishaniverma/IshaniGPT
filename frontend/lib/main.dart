import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_api.dart';
import 'models.dart';

const _ink = Color(0xFF17201D);
const _muted = Color(0xFF77817C);
const _green = Color(0xFF168B67);
const _canvas = Color(0xFFF8F9F7);
const _line = Color(0xFFE9ECE9);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IshaniGPTApp());
}

class IshaniGPTApp extends StatelessWidget {
  const IshaniGPTApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IshaniGPT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _green,
          primary: _green,
          surface: Colors.white,
        ),
        fontFamily: 'Roboto',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8F9F7),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _green, width: 1.5),
          ),
        ),
      ),
      home: const _AppBootstrap(),
    );
  }
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  final _api = ChatApi();
  UserProfile? _user;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (await _api.restoreSession()) {
        _user = await _api.currentUser();
      }
    } catch (error) {
      _error = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _signedIn(UserProfile user) => setState(() => _user = user);

  void _signedOut() => setState(() => _user = null);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _green)),
      );
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _BrandMark(size: 48),
                const SizedBox(height: 20),
                const Text(
                  'Couldn’t connect to IshaniGPT',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Make sure the API is running, then try again.',
                  style: TextStyle(color: _muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _restoreSession,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_user == null) {
      return AuthScreen(api: _api, onSignedIn: _signedIn);
    }
    return ChatScreen(api: _api, user: _user!, onSignedOut: _signedOut);
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.api, required this.onSignedIn, super.key});

  final ChatApi api;
  final ValueChanged<UserProfile> onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _creatingAccount = false;
  bool _obscurePassword = true;
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final user = _creatingAccount
          ? await widget.api.signUp(
              _nameController.text.trim(),
              _emailController.text.trim(),
              _passwordController.text,
            )
          : await widget.api.signIn(
              _emailController.text.trim(),
              _passwordController.text,
            );
      if (mounted) widget.onSignedIn(user);
    } on ChatApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 780;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Padding(
                      padding: EdgeInsets.all(desktop ? 28 : 16),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 570),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: _line),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: _ink.withValues(alpha: .04),
                              blurRadius: 32,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Row(
                          children: [
                            if (desktop)
                              const Expanded(
                                child: SizedBox(
                                  height: 570,
                                  child: _WelcomePanel(),
                                ),
                              ),
                            Expanded(
                              child: SizedBox(
                                height: 570,
                                child: Center(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(36),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 390,
                                      ),
                                      child: _buildForm(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BrandLockup(),
        const SizedBox(height: 38),
        Text(
          _creatingAccount ? 'Create your account' : 'Welcome back',
          style: const TextStyle(
            color: _ink,
            fontSize: 30,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          _creatingAccount
              ? 'Your ideas deserve a thoughtful conversation.'
              : 'Sign in to pick up where you left off.',
          style: const TextStyle(color: _muted, fontSize: 15),
        ),
        const SizedBox(height: 28),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_creatingAccount) ...[
                const _FieldLabel('Your name'),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Alex Morgan',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Please enter your name'
                      : null,
                ),
                const SizedBox(height: 18),
              ],
              const _FieldLabel('Email address'),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!RegExp(
                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                  ).hasMatch(value.trim())) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              const _FieldLabel('Password'),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: _creatingAccount
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: _creatingAccount
                      ? 'At least 8 characters'
                      : 'Enter your password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your password';
                  }
                  if (_creatingAccount && value.length < 8) {
                    return 'Use at least 8 characters';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF2F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFAC3D31),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _working ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _ink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _working
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _creatingAccount ? 'Create account' : 'Sign in',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _creatingAccount
                  ? 'Already have an account?'
                  : 'New to IshaniGPT?',
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
            TextButton(
              onPressed: _working
                  ? null
                  : () => setState(() {
                      _creatingAccount = !_creatingAccount;
                      _error = null;
                    }),
              child: Text(
                _creatingAccount ? 'Sign in' : 'Create account',
                style: const TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'By continuing, you agree to use IshaniGPT responsibly.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF172D25),
      padding: const EdgeInsets.all(48),
      child: Stack(
        children: [
          Positioned(
            top: 12,
            right: 0,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: .08),
                  width: 1,
                ),
              ),
            ),
          ),
          Positioned(
            top: 48,
            right: 36,
            child: Container(
              width: 138,
              height: 138,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _green.withValues(alpha: .28),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _BrandLockup(light: true),
              const Spacer(),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFFA7E8CB),
                  size: 27,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'A little help can\nchange everything.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 35,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Think out loud, explore an idea, or get unstuck. Your AI companion is ready when you are.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .68),
                  fontSize: 15,
                  height: 1.7,
                ),
              ),
              const Spacer(),
              Text(
                'Curiosity looks good on you.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .55),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.api,
    required this.user,
    required this.onSignedOut,
    super.key,
  });

  final ChatApi api;
  final UserProfile user;
  final VoidCallback onSignedOut;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  final _scrollController = ScrollController();
  List<Conversation> _conversations = [];
  Conversation? _selectedConversation;
  List<ChatMessage> _messages = [];
  bool _loadingChats = true;
  bool _loadingMessages = false;
  bool _sending = false;
  String? _chatError;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    try {
      final conversations = await widget.api.conversations();
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _loadingChats = false;
        });
      }
    } on ChatApiException catch (error) {
      if (mounted) {
        setState(() {
          _loadingChats = false;
          _chatError = error.message;
        });
      }
    }
  }

  Future<void> _newChat() async {
    try {
      final conversation = await widget.api.createConversation();
      if (!mounted) return;
      setState(() {
        _selectedConversation = conversation;
        _messages = [];
        _chatError = null;
      });
      await _loadConversations();
      _inputFocus.requestFocus();
    } on ChatApiException catch (error) {
      _showError(error.message);
    }
  }

  Future<void> _openConversation(Conversation conversation) async {
    setState(() {
      _selectedConversation = conversation;
      _messages = [];
      _loadingMessages = true;
      _chatError = null;
    });
    try {
      final messages = await widget.api.messages(conversation.threadId);
      if (mounted && _selectedConversation?.threadId == conversation.threadId) {
        setState(() {
          _messages = messages;
          _loadingMessages = false;
        });
        _scrollToBottom();
      }
    } on ChatApiException catch (error) {
      if (mounted) {
        setState(() {
          _loadingMessages = false;
          _chatError = error.message;
        });
      }
    }
  }

  Future<void> _send([String? suggestedText]) async {
    final text = (suggestedText ?? _inputController.text).trim();
    if (text.isEmpty || _sending) return;

    var conversation = _selectedConversation;
    if (conversation == null) {
      try {
        conversation = await widget.api.createConversation();
        if (!mounted) return;
        setState(() {
          _selectedConversation = conversation;
          _conversations = [conversation!, ..._conversations];
        });
      } on ChatApiException catch (error) {
        _showError(error.message);
        return;
      }
    }

    _inputController.clear();
    final threadId = conversation.threadId;
    setState(() {
      _sending = true;
      _chatError = null;
      _messages = [
        ..._messages,
        ChatMessage(
          id: -DateTime.now().microsecondsSinceEpoch,
          role: 'user',
          content: text,
          createdAt: DateTime.now(),
        ),
      ];
    });
    _scrollToBottom();
    try {
      final assistant = ChatMessage(
        id: -DateTime.now().microsecondsSinceEpoch - 1,
        role: 'assistant',
        content: '',
        createdAt: DateTime.now(),
      );
      setState(() => _messages = [..._messages, assistant]);
      var assistantContent = '';
      await for (final delta in widget.api.sendMessageStream(threadId, text)) {
        if (!mounted) return;
        assistantContent += delta;
        setState(() {
          _messages = [
            ..._messages.take(_messages.length - 1),
            ChatMessage(
              id: assistant.id,
              role: 'assistant',
              content: assistantContent,
              createdAt: assistant.createdAt,
            ),
          ];
        });
        _scrollToBottom();
      }
      await _loadConversations();
      _scrollToBottom();
    } on ChatApiCancelledException {
      if (mounted) {
        setState(() {
          if (_messages.isNotEmpty && _messages.last.id < 0) {
            _messages = _messages.take(_messages.length - 1).toList();
          }
        });
      }
    } on ChatApiException catch (error) {
      if (mounted) {
        setState(() {
          if (_messages.isNotEmpty && _messages.last.id < 0) {
            _messages = _messages.take(_messages.length - 1).toList();
          }
          _chatError = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.api.signOut();
    } on ChatApiException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      widget.onSignedOut();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final sidebar = _Sidebar(
          user: widget.user,
          conversations: _conversations,
          selectedThreadId: _selectedConversation?.threadId,
          loading: _loadingChats,
          onNewChat: _newChat,
          onSelectChat: (conversation) {
            _openConversation(conversation);
            if (!desktop) Navigator.of(context).pop();
          },
          onSignOut: _signOut,
        );

        return Scaffold(
          key: _scaffoldKey,
          drawer: desktop ? null : Drawer(child: SafeArea(child: sidebar)),
          body: SafeArea(
            child: Row(
              children: [
                if (desktop) sidebar,
                Expanded(
                  child: Column(
                    children: [
                      _ChatTopBar(
                        user: widget.user,
                        desktop: desktop,
                        onNewChat: _newChat,
                        onOpenMenu: () =>
                            _scaffoldKey.currentState?.openDrawer(),
                      ),
                      Expanded(child: _buildConversation()),
                      _buildComposer(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConversation() {
    if (_loadingMessages) {
      return const Center(child: CircularProgressIndicator(color: _green));
    }
    if (_selectedConversation == null || _messages.isEmpty) {
      return _WelcomeChat(userName: widget.user.name, onSuggestion: _send);
    }
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            itemCount: _messages.length + (_sending ? 1 : 0),
            itemBuilder: (context, index) {
              if (_sending && index == _messages.length) {
                return const _TypingIndicator();
              }
              return _MessageTile(message: _messages[index], user: widget.user);
            },
          ),
        ),
        if (_chatError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _InlineError(message: _chatError!),
          ),
      ],
    );
  }

  Widget _buildComposer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: _line),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: _ink.withValues(alpha: .035),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Shortcuts(
                        shortcuts: const <ShortcutActivator, Intent>{
                          SingleActivator(LogicalKeyboardKey.enter):
                              _SendMessageIntent(),
                        },
                        child: Actions(
                          actions: <Type, Action<Intent>>{
                            _SendMessageIntent:
                                CallbackAction<_SendMessageIntent>(
                                  onInvoke: (_) {
                                    _send();
                                    return null;
                                  },
                                ),
                          },
                          child: TextField(
                            controller: _inputController,
                            focusNode: _inputFocus,
                            minLines: 1,
                            maxLines: 6,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.newline,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(
                              hintText: 'Message IshaniGPT...',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.fromLTRB(
                                19,
                                17,
                                10,
                                17,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 8, 8),
                      child: IconButton.filled(
                        onPressed: _sending ? null : () => _send(),
                        tooltip: 'Send message',
                        style: IconButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _green.withValues(alpha: .5),
                          minimumSize: const Size(42, 42),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_upward_rounded, size: 21),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'IshaniGPT can make mistakes. Check important information.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.user,
    required this.conversations,
    required this.selectedThreadId,
    required this.loading,
    required this.onNewChat,
    required this.onSelectChat,
    required this.onSignOut,
  });

  final UserProfile user;
  final List<Conversation> conversations;
  final String? selectedThreadId;
  final bool loading;
  final VoidCallback onNewChat;
  final ValueChanged<Conversation> onSelectChat;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F3F0),
        border: Border(right: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 0, 6, 22),
            child: _BrandLockup(),
          ),
          OutlinedButton.icon(
            onPressed: onNewChat,
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text('New chat'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
              side: const BorderSide(color: Color(0xFFDDE2DD)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 26, 8, 10),
            child: Text(
              'YOUR CHATS',
              style: TextStyle(
                color: _muted,
                fontSize: 10,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _green,
                    ),
                  )
                : conversations.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Your conversations will show up here.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      final selected =
                          conversation.threadId == selectedThreadId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Material(
                          color: selected
                              ? const Color(0xFFE3EAE4)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () => onSelectChat(conversation),
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    color: _muted,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      conversation.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _ink,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(color: _line, height: 20),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showAccountMenu(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  _UserAvatar(name: user.name, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.more_horiz_rounded, color: _muted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAccountMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.logout_rounded),
          title: const Text('Sign out'),
          onTap: () {
            Navigator.pop(context);
            onSignOut();
          },
        ),
      ),
    );
  }
}

class _ChatTopBar extends StatelessWidget {
  const _ChatTopBar({
    required this.user,
    required this.desktop,
    required this.onNewChat,
    required this.onOpenMenu,
  });

  final UserProfile user;
  final bool desktop;
  final VoidCallback onNewChat;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: _canvas,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          if (!desktop) ...[
            IconButton(
              onPressed: onOpenMenu,
              tooltip: 'Open chat history',
              icon: const Icon(Icons.menu_rounded, color: _ink),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            'IshaniGPT',
            style: TextStyle(
              color: _ink,
              fontSize: desktop ? 16 : 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 7),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: _muted,
          ),
          const Spacer(),
          if (desktop)
            TextButton.icon(
              onPressed: onNewChat,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New chat'),
              style: TextButton.styleFrom(foregroundColor: _ink),
            )
          else
            _UserAvatar(name: user.name, size: 34),
        ],
      ),
    );
  }
}

class _WelcomeChat extends StatelessWidget {
  const _WelcomeChat({required this.userName, required this.onSuggestion});

  final String userName;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final firstName = userName.trim().split(RegExp(r'\s+')).first;
    final suggestions = [
      (Icons.lightbulb_outline_rounded, 'Help me think through an idea'),
      (Icons.edit_note_rounded, 'Write something with me'),
      (Icons.menu_book_rounded, 'Explain a tricky topic simply'),
      (Icons.explore_outlined, 'Plan a great weekend'),
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 32, 22, 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 62,
                width: 62,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2F1E9),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: _green,
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Good to see you, $firstName.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 29,
                  letterSpacing: -.7,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'What would you like to explore today?',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 15),
              ),
              const SizedBox(height: 30),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: suggestions.map((suggestion) {
                  return ActionChip(
                    onPressed: () => onSuggestion(suggestion.$2),
                    avatar: Icon(suggestion.$1, color: _green, size: 18),
                    label: Text(suggestion.$2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 10,
                    ),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: _line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    labelStyle: const TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, required this.user});

  final ChatMessage message;
  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 580),
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF1ED),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: SelectableText(
                  message.content,
                  style: const TextStyle(
                    color: _ink,
                    height: 1.55,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _UserAvatar(name: user.name, size: 32),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandMark(size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6, bottom: 5),
                  child: Text(
                    'IshaniGPT',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SelectableText(
                  message.content,
                  style: const TextStyle(
                    color: _ink,
                    height: 1.7,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 22),
      child: Row(
        children: [
          _BrandMark(size: 32),
          SizedBox(width: 12),
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _green),
          ),
          SizedBox(width: 10),
          Text('Thinking...', style: TextStyle(color: _muted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFAC3D31), fontSize: 13),
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({this.light = false});

  final bool light;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BrandMark(size: 34),
        const SizedBox(width: 10),
        Text(
          'IshaniGPT',
          style: TextStyle(
            color: light ? Colors.white : _ink,
            fontWeight: FontWeight.w700,
            fontSize: 17,
            letterSpacing: -.35,
          ),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _green,
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        color: Colors.white,
        size: size * .55,
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFDCEAE0),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: const TextStyle(
          color: Color(0xFF315B46),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: _ink,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}
