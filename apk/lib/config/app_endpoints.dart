const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://digitallami.com',
);

const String kSocketServerBaseUrl = String.fromEnvironment(
  'SOCKET_SERVER_URL',
  defaultValue: 'https://adminnew.marriagestation.com.np',
);

const String kApi2BaseUrl = '$kApiBaseUrl/Api2';
const String kApi3BaseUrl = '$kApiBaseUrl/Api3';
const String kApi9BaseUrl = '$kApiBaseUrl/api9';
const String kRequestBaseUrl = '$kApiBaseUrl/request';
