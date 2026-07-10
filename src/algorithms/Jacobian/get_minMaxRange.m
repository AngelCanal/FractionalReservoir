function min_max_range = get_minMaxRange(params)
    % Returns bounds per state variable for the SRNN state vector used in
    % benettin_algorithm. By default the SRNN has no hard bounds, so all
    % entries are initialized to NaN, but the vector must match the full
    % state layout: S = [a_E(:); a_I(:); b_E(:); b_I(:); x(:)].
    %
    % You can edit the sections below to set bounds for specific groups.

    layout = state_layout(params);
    N_sys_eqs = layout.n_total;

    % Initialize with NaN (no bounds by default)
    min_max_range = nan(N_sys_eqs, 2);

    % Example of setting bounds per group (commented out):
    % min_max_range(layout.idx_a_E, :) = [... lower upper ...];
end