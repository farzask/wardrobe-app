import 'package:fitcheck/core/config/app_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

/// `.env` is bundled into the app as an asset, so anything in it ships to every phone. The split
/// between the client `.env` and `backend/.env` is what keeps SUPABASE_JWT_SECRET off devices, and
/// these tests are what keep the split honest.
///
/// `loadFromString` is used instead of `load` because the latter reads a Flutter asset, which is
/// not available in a unit test — and pinning the behaviour to real file contents would make these
/// tests fail for reasons unrelated to the logic.
void main() {
  tearDown(dotenv.clean);

  group('reading configuration', () {
    test('reads values from .env', () {
      dotenv.loadFromString(
        envString: 'SUPABASE_URL=https://abc.supabase.co\n'
            'SUPABASE_ANON_KEY=anon-key\n'
            'BACKEND_URL=http://localhost:8000\n',
      );

      expect(AppConfig.supabaseUrl, 'https://abc.supabase.co');
      expect(AppConfig.supabaseAnonKey, 'anon-key');
      expect(AppConfig.backendUrl, 'http://localhost:8000');
      expect(AppConfig.isConfigured, isTrue);
      expect(AppConfig.missingKeys, isEmpty);
    });

    test('trims surrounding whitespace', () {
      // A trailing space on a URL produces a request to a host that does not exist, and the error
      // gives no hint that a stray keystroke caused it.
      dotenv.loadFromString(envString: 'BACKEND_URL=  http://localhost:8000  \n');
      expect(AppConfig.backendUrl, 'http://localhost:8000');
    });

    test('names every missing key rather than failing generically', () {
      dotenv.loadFromString(envString: 'SUPABASE_URL=https://abc.supabase.co\n');
      expect(AppConfig.isConfigured, isFalse);
      expect(AppConfig.missingKeys, ['SUPABASE_ANON_KEY', 'BACKEND_URL']);
    });

    test('treats an empty value as missing', () {
      // `KEY=` is the state .env.example ships in, and it must not read as configured.
      dotenv.loadFromString(
        envString: 'SUPABASE_URL=\nSUPABASE_ANON_KEY=\nBACKEND_URL=\n',
      );
      expect(AppConfig.missingKeys, hasLength(3));
    });

    test('does not throw when .env was never loaded', () {
      // The normal case in unit tests, and the case where --dart-define supplies everything.
      // `dotenv.env` throws when uninitialised, so this has to be guarded.
      expect(dotenv.isInitialized, isFalse);
      expect(AppConfig.supabaseUrl, '');
      expect(AppConfig.isConfigured, isFalse);
      expect(AppConfig.envFileLoaded, isFalse);
    });

    test('distinguishes "no .env" from ".env is incomplete"', () {
      // The two need different fixes, so the startup screen tells them apart.
      expect(AppConfig.envFileLoaded, isFalse);
      dotenv.loadFromString(envString: 'SUPABASE_URL=https://abc.supabase.co\n');
      expect(AppConfig.envFileLoaded, isTrue);
      expect(AppConfig.isConfigured, isFalse);
    });
  });

  group('reporting where each value came from', () {
    // Diagnosing bad config is almost never "what is the value" but "which source won". These
    // three states look identical in a bare missing-keys list and have completely different fixes.
    test('distinguishes a stale build from an empty value from a real gap', () {
      expect(AppConfig.sources['BACKEND_URL'], 'not set (.env never loaded)');

      dotenv.loadFromString(
        envString: 'SUPABASE_URL=https://abc.supabase.co\nBACKEND_URL=\n',
      );

      // Present in .env with a value → the file is being read.
      expect(AppConfig.sources['SUPABASE_URL'], '.env');
      // Present but blank → edit the file.
      expect(AppConfig.sources['BACKEND_URL'], '.env, but empty');
      // Absent from a file that is otherwise loading → the key was never added.
      expect(AppConfig.sources['SUPABASE_ANON_KEY'], 'not set');
    });

    test('reports every key, including the ones that resolved', () {
      dotenv.loadFromString(envString: 'BACKEND_URL=http://localhost:8000\n');
      expect(
        AppConfig.sources.keys,
        containsAll(['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'BACKEND_URL']),
      );
    });
  });

  group('server secrets must never reach the client', () {
    test('flags the JWT secret', () {
      // The most dangerous of the three: holding it lets you sign a token for any account, which
      // defeats every RLS policy in migrations 002-007 at once.
      dotenv.loadFromString(
        envString: 'SUPABASE_URL=https://abc.supabase.co\n'
            'SUPABASE_ANON_KEY=anon-key\n'
            'BACKEND_URL=http://localhost:8000\n'
            'SUPABASE_JWT_SECRET=super-secret\n',
      );
      expect(AppConfig.leakedServerSecrets, contains('SUPABASE_JWT_SECRET'));
    });

    test('flags the service-role key', () {
      dotenv.loadFromString(envString: 'SUPABASE_SERVICE_ROLE_KEY=service-role\n');
      expect(AppConfig.leakedServerSecrets, contains('SUPABASE_SERVICE_ROLE_KEY'));
    });

    test('flags the Gemini key', () {
      // Nothing in the app calls Gemini, so its presence here is always a paste error — and the
      // key is billable.
      dotenv.loadFromString(envString: 'GEMINI_API_KEY=AIza-whatever\n');
      expect(AppConfig.leakedServerSecrets, contains('GEMINI_API_KEY'));
    });

    test('reports every secret found, not just the first', () {
      dotenv.loadFromString(
        envString: 'SUPABASE_JWT_SECRET=a\n'
            'SUPABASE_SERVICE_ROLE_KEY=b\n'
            'GEMINI_API_KEY=c\n',
      );
      expect(AppConfig.leakedServerSecrets, hasLength(3));
    });

    test('a correctly split .env is clean', () {
      dotenv.loadFromString(
        envString: 'SUPABASE_URL=https://abc.supabase.co\n'
            'SUPABASE_ANON_KEY=anon-key\n'
            'BACKEND_URL=http://localhost:8000\n',
      );
      expect(AppConfig.leakedServerSecrets, isEmpty);
    });

    test('an empty secret is not a leak', () {
      // `.env.example` carries these names with no values in its comments; a blank should not
      // block startup.
      dotenv.loadFromString(envString: 'SUPABASE_JWT_SECRET=\n');
      expect(AppConfig.leakedServerSecrets, isEmpty);
    });

    test('is inert when .env was never loaded', () {
      expect(AppConfig.leakedServerSecrets, isEmpty);
    });
  });
}
