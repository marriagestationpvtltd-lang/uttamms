// Add these models at the top of your file or in a separate models file


// Update your state variables in _PartnerPreferencesPageState
List<Country> _countries = [];
List<StateModel> _allStates = []; // Store all loaded states
List<City> _allCities = []; // Store all loaded cities

// Keep your existing selected lists
List<String> _selectedCountry = [];
List<String> _selectedState = [];
List<String> _selectedCity = [];

bool _loadingCountries = false;
bool _loadingStates = false;
bool _loadingCities = false;
class Country {
  final String id;
  final String name;

  Country({required this.id, required this.name});
}

class StateModel {
  final int id;
  final String name;
  final String countryId; // To track which country this state belongs to

  StateModel({required this.id, required this.name, required this.countryId});
}

class City {
  final int id;
  final String name;
  final int stateId; // To track which state this city belongs to

  City({required this.id, required this.name, required this.stateId});
}




// Add these methods to fetch data from APIs
