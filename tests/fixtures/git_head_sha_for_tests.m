function sha = git_head_sha_for_tests()
    sha = '';
    try
        [status, out] = system('git rev-parse HEAD');
        if status == 0
            sha = strtrim(out);
        end
    catch
        sha = '';
    end
    if isempty(sha)
        sha = 'unknown_commit';
    end
end
