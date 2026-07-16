function U = diagnostic_calibration_input(cfg, op, seed)
    input_seed = seed + op.input_seed_offset;
    stream = RandStream('mt19937ar', 'Seed', input_seed);
    U = op.input_min + (op.input_max - op.input_min) * ...
        rand(stream, op.total_steps, cfg.base.n_inputs);
end
