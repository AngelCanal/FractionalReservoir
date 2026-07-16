function [stream, provenance] = derive_inference_rng_seed(namespace, master_seed)
%DERIVE_INFERENCE_RNG_SEED  Deterministic local RandStream from namespace hash.
%
%   [stream, provenance] = derive_inference_rng_seed(namespace, master_seed)
%
% Does not call rng() globally. Maps SHA-256 digest into [1, 2^31-2].

    if nargin < 2 || isempty(master_seed)
        master_seed = 55021;
    end

    if ~isstruct(namespace)
        error('derive_inference_rng_seed:InvalidNamespace', ...
            'namespace must be a struct.');
    end

    payload = namespace;
    payload.master_seed = master_seed;
    digest = canonical_sha256(payload);

    hex8 = digest(1:8);
    seed_int = hex2dec(hex8);
    max_seed = 2^31 - 2;
    derived_seed = mod(seed_int, max_seed) + 1;

    stream = RandStream('mt19937ar', 'Seed', derived_seed);

    provenance = struct();
    provenance.digest = digest;
    provenance.hex8 = hex8;
    provenance.derived_seed = derived_seed;
    provenance.master_seed = master_seed;
    provenance.algorithm = 'mt19937ar';
    provenance.namespace = namespace;
end
