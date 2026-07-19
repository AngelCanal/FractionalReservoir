function key = temporal_memory_checkpoint_key(kind, varargin)
%TEMPORAL_MEMORY_CHECKPOINT_KEY  Canonical checkpoint identity keys.
%
%   key = temporal_memory_checkpoint_key('shared_task_controls')
%   key = temporal_memory_checkpoint_key('cell', cell_name, seed)
%   key = temporal_memory_checkpoint_key('conventional', seed)
%   key = temporal_memory_checkpoint_key('no_recurrent', seed)
%   key = temporal_memory_checkpoint_key('shuffled_target', seed)

    kind = char(kind);
    switch kind
        case 'shared_task_controls'
            key = 'shared_task_controls';
        case 'cell'
            key = sprintf('cell:%s|seed:%d', char(varargin{1}), varargin{2});
        case 'conventional'
            key = sprintf('conventional|seed:%d', varargin{1});
        case 'no_recurrent'
            key = sprintf('no_recurrent|seed:%d', varargin{1});
        case 'shuffled_target'
            key = sprintf('shuffled_target|seed:%d', varargin{1});
        otherwise
            error('temporal_memory_checkpoint_key:UnknownKind', ...
                'Unknown checkpoint key kind %s.', kind);
    end
end
