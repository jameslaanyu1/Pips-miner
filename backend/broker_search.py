from time import monotonic
from urllib.parse import urlencode

from flask import jsonify, request

from backend.app import app, meta_raw, METAAPI_PROVISIONING_URL

_CACHE = {}
_CACHE_TTL_SECONDS = 300


@app.get('/api/v1/broker-servers')
def broker_servers():
    query = str(request.args.get('query', '')).strip()
    if len(query) < 2:
        return jsonify({'ok': False, 'error': 'Broker search query must contain at least 2 characters.'}), 400
    if len(query) > 80:
        return jsonify({'ok': False, 'error': 'Broker search query is too long.'}), 400

    key = query.casefold()
    now = monotonic()
    cached = _CACHE.get(key)
    if cached and now - cached[0] < _CACHE_TTL_SECONDS:
        return jsonify({'ok': True, 'brokers': cached[1], 'cached': True})

    try:
        response = meta_raw(
            'GET',
            METAAPI_PROVISIONING_URL,
            f"/known-mt-servers/5/search?{urlencode({'query': query})}",
        )
        if response.status_code != 200:
            return jsonify({
                'ok': False,
                'error': f'MetaApi broker search failed ({response.status_code}).',
            }), 502

        payload = response.json()
        brokers = []
        if isinstance(payload, dict):
            for broker, servers in payload.items():
                if not isinstance(servers, list):
                    continue
                cleaned_servers = [str(server).strip() for server in servers if str(server).strip()]
                if cleaned_servers:
                    brokers.append({
                        'broker': str(broker),
                        'servers': cleaned_servers[:10],
                    })

        brokers = brokers[:10]
        _CACHE[key] = (now, brokers)
        return jsonify({'ok': True, 'brokers': brokers, 'cached': False})
    except Exception as exc:
        app.logger.exception('Broker server search failed')
        return jsonify({
            'ok': False,
            'error': 'Could not search MT5 broker servers right now.',
            'details': str(exc),
        }), 502
