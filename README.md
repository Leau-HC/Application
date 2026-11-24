# Application

Toute idee d'application dans differents classeur de code

## Messagerie universitaire (Flutter + Firebase)

Application de démonstration Flutter pour Android et iOS : connexion par e-mail, conversations privées, messages texte et partage d’images/vidéos. Le thème marine est sélectionné par défaut ; l’utilisateur peut choisir un thème clair ou noir.

## Préparer Firebase

1. Installez Android Studio et, dans son SDK Manager, Android SDK, Platform-Tools et au moins un SDK de plateforme. Ensuite, lancez `flutter doctor --android-licenses` et acceptez les licences. Branchez un téléphone en mode développeur ou créez un émulateur dans Android Studio.
2. Créez un projet dans la [console Firebase](https://console.firebase.google.com/), ajoutez une application Android avec l’identifiant `com.example.university_messenger`, puis activez **Authentication > Sign-in method > Email/Password**, **Cloud Firestore** et **Cloud Storage**.
3. Installez Node.js et Firebase CLI (`npm install -g firebase-tools`), connectez-vous avec `firebase login`, sélectionnez votre projet (`firebase use --add`) et déployez les règles et index configurés dans `firebase.json` avec `firebase deploy --only firestore:rules,firestore:indexes,storage`.
4. Activez FlutterFire CLI avec `dart pub global activate flutterfire_cli`, puis, depuis ce dossier, exécutez :

   ```sh
   flutter pub get
   flutterfire configure
   flutter run
   ```

   `flutterfire configure` génère `lib/firebase_options.dart`, ignoré par Git. Choisissez Android (et iOS si vous compilerez sur macOS avec Xcode).
5. Lancez `flutter run` sur l’émulateur ou le téléphone connecté. Pour une compilation iOS, utilisez macOS et Xcode.
6. Pour tester avec `leauhyembi@gmail.com`, choisissez **Créer un compte** avec cette adresse et un mot de passe que vous seul connaissez, puis validez le lien reçu par e-mail. Pour les connexions suivantes, choisissez **Se connecter**. L’adresse préremplie ne crée pas de compte et aucun mot de passe n’est enregistré dans le code.
7. Dans **Profil**, copiez votre identifiant Firebase et partagez-le avec une autre personne inscrite. Pour démarrer une conversation, saisissez son identifiant Firebase. Les conversations sont privées entre leurs deux membres.

## Structure et règles

- `users/{uid}` contient uniquement le nom d’affichage ; seul l’utilisateur et les membres d’une conversation commune peuvent le lire.
- `conversations/{uidA}__{uidB}/messages/{messageId}` contient les messages. Les identifiants de conversation sont déterministes afin qu’une paire d’utilisateurs ne crée pas de doublons.
- Les fichiers sont stockés sous `conversations/{conversationId}/{uid}/{fileName}`. Le client conserve leur chemin, pas une URL publique de téléchargement. Les règles Storage n’autorisent que les membres à lire les fichiers et leur propriétaire à les déposer.
- Les comptes doivent avoir vérifié leur adresse e-mail avant d’accéder aux conversations. Les règles Firestore/Storage doivent être déployées avant les tests.

Les règles sont une base pour ce prototype. Avant un déploiement public, testez-les avec Firebase Emulator Suite et prévoyez notamment modération, signalement, politique de confidentialité, sauvegardes et limites anti-abus.
