Future<String> persistenceSnapshot() async => 'native: no browser storage';

bool locationOmits(String sensitive) => true; // Native has no browser location.
