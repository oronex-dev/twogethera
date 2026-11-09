const localHosts = new Set(['127.0.0.1', 'localhost', 'kong']);

/** Rejects misbound hosted function configuration without logging endpoint data. */
export function validateProjectTarget(endpointValue, environment, expectedProjectRef) {
  let endpoint;
  try {
    endpoint = new URL(endpointValue);
  } catch (_) {
    throw new Error('Supabase project target is invalid.');
  }

  const hasOnlyOrigin =
    (endpoint.pathname === '' || endpoint.pathname === '/') &&
    endpoint.search === '' && endpoint.hash === '' &&
    endpoint.username === '' && endpoint.password === '';

  if (environment === 'development') {
    if (endpoint.protocol !== 'http:' || !localHosts.has(endpoint.hostname) || !hasOnlyOrigin) {
      throw new Error('Development functions may target only local Supabase.');
    }
    return;
  }

  if (environment !== 'staging' && environment !== 'production') {
    throw new Error('Supabase project environment is invalid.');
  }
  if (!/^[a-z0-9]{20}$/.test(expectedProjectRef ?? '')) {
    throw new Error('Expected Supabase project reference is missing or invalid.');
  }
  if (
    endpoint.protocol !== 'https:' ||
    endpoint.hostname !== `${expectedProjectRef}.supabase.co` ||
    (endpoint.port !== '' && endpoint.port !== '443') ||
    !hasOnlyOrigin
  ) {
    throw new Error('Supabase project target does not match the approved reference.');
  }
}

export function allowedOriginsForEnvironment(configuredOrigins, environment) {
  const origins = new Set(
    String(configuredOrigins ?? '')
      .split(',')
      .map((origin) => origin.trim())
      .filter(Boolean),
  );
  if (environment === 'development') {
    origins.add('http://127.0.0.1:8081');
  }
  return origins;
}
