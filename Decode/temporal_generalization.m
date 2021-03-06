function [ results, train_idx, test_idx ] = temporal_generalization( data, labels, varargin )
% Performs temporal generalization SVM decoding of MEG data (train on each time point/window, test on all others). Uses hold-out validation (train on half, test on half).
% Inputs: data, labels. Data format: channels/sources x time x trials
% Optional: 'sensor_idx', structure obtained using get_sensor_info - for channel selection. You can also just provide numerical indices, in which case you don't need the structure. 
%                        If you want to subselect features on source space data, you need to manually provide numerical indice (i.e. 'channels', [1:1000]). 
%           'train_idx','test_idx': the script runs a hold-out cross-validation for speed and here you can specify the indices. 
%                                    If not specify, it does a random split-half CV and saves the indices.
%           'pseudo', default [], create pseudotrials: example [5 100], average groups of 5 trials with 100 random assignments of trials to groups
%           'mnn', default true, perform multivariate noise normalization (recommended, Guggenmos et al. 2018)
%           'decoding_window' (limits; default: [] - all timepoints). In  sampled time points (OR in seconds - only if you also provide time axis).
%           'window_length' (in sampled time points; default: 1).
%           'time', time axis, if you want to give the decoding window in seconds, you also need to provide a time axis, matching the second dimension of the data).
%           'channels', channel set (string or cell array of strings; default: 'MEG').
%
%           Below are other name-value pairs that control the SVM settings, with defaults:
%           
%           solver = 1; %only applies to liblinear: 1: L2 dual-problem; 2: L2 primal; 3:L2RL1L...
%           boxconstraint = 1; --> C-parameter: Note, we don't have any options for optimizing this, need to write it separately if needed
%           standardize = true; --> standardize features using mean and SD of training set (recommended)
%           weights = false; --> calculate weights (by retraining model on whole dataset)
%
% Outputs: time x time accuracy matrix, train_idx and test_idx (we are using a split-half hold-out approach for speed and the indices are saved)
%          training time on y-axis (rows), test time on x-axis (columns)
%
% DC Dima 2018 (diana.c.dima@gmail.com)

%parse inputs
dec_args = args.decoding_args;
svm_par = args.svm_args;
list = [fieldnames(dec_args); fieldnames(svm_par)];
p = inputParser;

for i = 1:length(properties(args.decoding_args))
    addParameter(p, list{i}, dec_args.(list{i}));
end
for ii = i+1:length(properties(args.decoding_args))+length(properties(args.svm_args))
    addParameter(p, list{ii}, svm_par.(list{ii}));
end
addParameter(p, 'sensor_idx', []);
addParameter(p, 'train_idx', []);
addParameter(p, 'test_idx', []);
parse(p, varargin{:});
dec_args = p.Results;
svm_par = rmfield(struct(dec_args), {'window_length','channels','decoding_window', 'time', 'sensor_idx', 'pseudo', 'test_idx', 'train_idx','mnn'}); %converted struct will be fed into decoding function
clear p;

if ~isa(data, 'double')
    data = double(data);
end;

%get channel indices and time axis. Numerical channel indices take priority
if ~iscell(dec_args.channels) && ~ischar(dec_args.channels)
    chan_idx = dec_args.channels;
end;
if (~isempty(dec_args.sensor_idx)) && (~strcmp (dec_args.channels, 'MEG'))
    if ~exist('chan_idx', 'var')
        chan = [];
        for i = 1:length(dec_args.channels)
            idx = cellfun('isempty',strfind({sensor_idx.label},dec_args.channels{i}));
            chan = [chan chan_idx(~idx)]; %#ok<AGROW>
        end;
        chan_idx = chan;
    end;
else
    if ~exist('chan_idx', 'var')
        chan_idx = 1:size(data,1);
    end;
end

%create time axis
if ~isempty(dec_args.time)
    time = dec_args.time;
elseif ~isempty(dec_args.sensor_idx) && isfield(sensor_idx, 'time')
    time = sensor_idx(1).time;
else
    time = 1:size(data,2);
end

if length(time)~=size(data,2)
    time = 1:size(data,2);
    fprintf('Warning: time axis does not match dataset size. Replacing with default time axis...');
end


if ~isempty(dec_args.decoding_window)
    lims(1) = nearest(time,dec_args.decoding_window(1));
    lims(2) = nearest(time,dec_args.decoding_window(2));       
else
    lims = [1 size(data,2)];
end

%we use a hold-out method that trains on half and tests on the other half, for speed reasons; other methods such as nested kfold can be used, and indices can be provided
if isempty (dec_args.train_idx)
    classes = unique(labels); idx1 = find(labels==classes(1)); idx2 = find(labels==classes(2));
    train_idx = [idx1(randperm(floor(length(idx1)/2))); idx2(randperm(floor(length(idx2)/2)))];
    test_idx = [idx1; idx2]; test_idx(train_idx) = [];
else
    train_idx = dec_args.train_idx;
    test_idx = dec_args.test_idx;
end

if ~isempty(dec_args.pseudo)
    
    fprintf('\nCreating pseudotrials....\r');
    [train_data, train_labels] = create_pseudotrials(data(chan_idx,:,train_idx), labels(train_idx), dec_args.pseudo(1), dec_args.pseudo(2));
    [test_data, test_labels] = create_pseudotrials(data(chan_idx,:,test_idx), labels(test_idx), dec_args.pseudo(1), dec_args.pseudo(2));
    clear data labels;
else
    train_data = data(:,:,train_idx);
    test_data = data(:,:,test_idx); 
    train_labels = labels(train_idx);
    test_labels = labels(test_idx);
end

if dec_args.mnn
        [train_data,test_data] = whiten_data(train_data,train_labels,test_data);
end

train_data = arrayfun(@(i) reshape(train_data(:,i:i+dec_args.window_length-1,:), size(train_data,1)*dec_args.window_length, size(train_data,3))', lims(1):dec_args.window_length:lims(2)-dec_args.window_length+1, 'UniformOutput', false); %features are channelsxtime,observations are trials    
test_data = arrayfun(@(i) reshape(test_data(:,i:i+dec_args.window_length-1,:), size(test_data,1)*dec_args.window_length, size(test_data,3))', lims(1):dec_args.window_length:lims(2)-dec_args.window_length+1, 'UniformOutput', false); %features are channelsxtime,observations are trials    

results = zeros(length(train_data), length(train_data));

%and here we run the classifier -first train on all time points and store the models
svm_model = arrayfun(@(t) svm_train(train_data{t}, train_labels, svm_par), 1:length(train_data), 'UniformOutput', false);
fprintf('\nFinished training all models...')  
fprintf('\nNow testing...')

%testing on all time points
for t = 1:length(svm_model)
    
    if mod(t,100)==0
        fprintf('\n%d out of %d...', t, length(svm_model))
    end;
    
    for i = 1:length(test_data)
        
        %standardize test data, using values based on training data
        if svm_par.standardize
            test_data_i = (test_data{i} - repmat(min(train_data{t}, [], 1), size(test_data{i}, 1), 1)) ./ repmat(max(train_data{t}, [], 1) - min(train_data{t}, [], 1), size(test_data{i}, 1), 1);
        end;
        
        [~, accuracy, ~] = predict(test_labels, sparse(test_data_i), svm_model{t}, '-q 1');
        results(t,i) = accuracy(1);

    end;
    
end;
            
end

