import 'package:flutter_dotenv/flutter_dotenv.dart';

const kBaseUrl = 'http://localhost:3000';//'https://trailblaze.azurewebsites.net';

final String kAppToken = dotenv.env['TRAILBLAZE_APP_TOKEN'] ?? '';

final kRequestHeaderBasic = <String, String>{
  'Content-Type': 'application/json',
  'TRAILBLAZE-APP-TOKEN': kAppToken,
};
