function lam = resolve_baseline_lambda_grid(options, cfg)
% RESOLVE_BASELINE_LAMBDA_GRID  Explicit lambda grid for matched baselines.
%
% Uses options.lambda_grid if nonempty; else cfg.lengths.lambda_grid if nonempty;
% else Phase 4A default [0, logspace(-12, 2, 15)].

    lam = [];
    if nargin >= 1 && isstruct(options) && isfield(options, 'lambda_grid') && ...
            ~isempty(options.lambda_grid)
        lam = options.lambda_grid(:);
        return;
    end
    if nargin >= 2 && isstruct(cfg) && isfield(cfg, 'lengths') && ...
            isfield(cfg.lengths, 'lambda_grid') && ~isempty(cfg.lengths.lambda_grid)
        lam = cfg.lengths.lambda_grid(:);
        return;
    end
    lam = [0; logspace(-12, 2, 15)'];
end
