function [stats] = run_stats(accuracy, varargin)
% TO DO: ADD CLUSTER CORRECTION & ADD ONSET BOOTSTRAPPING
% Inputs: accuracy can be: subjects x time, subjects x space x time, subjects x time x time
% This is strictly fixed effects - add a possibility to loop through subjects...

addParameter(p, 'method','omnibus'); %cluster, omnibus, fdr, mixed_of, mixed_fo (specify for each dimension)
addParameter(p, 'alpha', 0.05);
addParameter(p, 'cluster_def_alpha', 0.05);
addParameter(p, 'spatial_def', []); %neighbours or sourcemodel for space-resolved data with cluster correction
addParameter(p, 'ci_latency', 'onset'); %none, onset
addParameter(p, 'num_iterations',5000);
addParameter(p, 'chance_level', 50);
addParameter(p, 'statistic', 'mean');
parse(p, varargin{:});
opt = p.Results;

%get size info
nd = ndims(accuracy); sz = size(accuracy); sz = sz(2:end); if numel(sz)==1, sz = [sz 1]; end; %size without subject dimension
if ~ismember(nd,[2 3])
    error('Accuracy must be a vector or matrix with subjects as first dimension and with maximum 3 dimensions');
end

%create null distribution; for omnibus thresholding only save maximal statistic
switch(opt.method)
    
    case 'omnibus'
        
        r_stat = nan([opt.num_iterations sz]); obs_stat = nan(sz); pval = nan(sz);
        
        for i = 1:size(accuracy,2)
            
            for ii = 1:size(accuracy,3)
                
                [r_stat(:,i,ii),obs_stat(i,ii),~] = randomize_accuracy(accuracy(:,i,ii),'num_iterations', opt.num_iterations, 'chance_level', opt.chance_level, 'statistic', opt.statistic);
            end
        end
        
        max_stat = squeeze(max(r_stat,[],2)); if size(max_stat,2)>1, max_stat = squeeze(max(max_stat,[],2)); end;
        
        for i = 1:size(accuracy,2)
            
            for ii = 1:size(accuracy,3)
                
                pval(i,ii) = (length(find(max_stat>=obs_stat(i,ii)))+1)/(opt.num_iterations+1);
            end
        end
        
        stats.pval = pval; stats.method = 'omnibus'; stats.mask = pval<opt.alpha;
        
        %BOOTSTRAP ONSETS FOR BOTH DIMENSIONS%
        if strcmp(opt.ci_latency,'onset')
            
            %[d1,d2] = find(stats.mask==1,1);
            
        end
        
        
    case 'fdr'
        
        pval = nan(sz);
        
        for i = 1:size(accuracy,2)
            
            for ii = 1:size(accuracy,3)
                
                [~,~,pval(i,ii)] = randomize_accuracy(accuracy(:,i,ii),'num_iterations', opt.num_iterations, 'chance_level', opt.chance_level, 'statistic', opt.statistic);
            end
        end
        
        [q,mask] = fdr(pval, opt.alpha);
        stats.pval = pval; stats.method = 'fdr'; stats.q = q; stats.mask = mask;
        
    case 'cluster'
        
        r_stat = nan([opt.num_iterations sz]); obs_stat = nan(sz);
        
        for i = 1:size(accuracy,2)
            
            for ii = 1:size(accuracy,3)
                
                [r_stat(:,i,ii),~,obs_stat(i,ii)] = randomize_accuracy(accuracy(:,i,ii),'num_iterations', opt.num_iterations, 'chance_level', opt.chance_level, 'statistic', opt.statistic);
            end
        end
        
        %look for positive clusters in observed and random data: one-tailed
        prc = 100* (1 - opt.cluster_def_alpha); %get cluster-setting percentile
        obs_map = obs_stat>=prctile(obs_stat,prc);
        r_map = nan([opt.num_iterations sz]);
        for i = 1:opt.num_iterations
            r_map(i,:,:) = r_stat>=prctile(obs_stat,prc);
        end
        
        max_r_cls = zeros(1,opt.num_iterations); %maximal cluster distribution, only maxsize for now
        
        %include channel, source (grid) data, and time by time cases
        if ~isempty(opt.spatial_def)
            
            %here we will use some Fieldtrip functions to not reinvent the wheel
            %first add the private FT functions to path
            [~,ftpath] = ft_version; addpath(fullfile(ftpath, private));
            
            if isfield (opt.spatial_def, 'neighblabel') % channel case
                
                cfg = [];
                cfg.neighbours = opt.spatial_def;
                cfg.channel = {opt.spatial_def(:).label};
                conn = channelconnectivity(cfg);
                
                obs_cls = bwconncomp(obs_map, conn);
                obs_labelmatrix = labelmatrix(obs_cls);
                
                for i = 1:opt.num_iterations
                    
                    r_tmp = squeeze(r_map(i,:,:));
                    r_cls =  bwconncomp(r_tmp, conn);
                    if ~isempty(r_cls.PixelIdxList)
                        max_r_cls(i) = max(cellfun(@length,r_cls.PixelIdxList));
                    end
                end
                
                
            elseif isfield(opt.spatial_def, 'dim') %sourcemodel case
                
                conn = conndef(length(opt.spatial_def.dim), 'max');
                obs_tmp = zeros(opt.spatial_def.dim);
                obs_tmp(opt.spatial_def.inside) = obs_map;
                
                obs_cls = bwconncomp(obs_tmp, conn);
                obs_labelmatrix = labelmatrix(obs_cls);
                obs_labelmatrix =  obs_labelmatrix(opt.spatial_def.inside);
                
                for i = 1:opt.num_iterations
                    
                    r_tmp = zeros(opt.spatial_def.dim); r_tmp(opt.spatial_def.inside) = squeeze(r_map(i,:,:));
                    r_cls =  bwconncomp(r_tmp, conn);
                    if ~isempty(r_cls.PixelIdxList)
                        max_r_cls(i) = max(cellfun(@length,r_cls.PixelIdxList));
                    end
                end
                
            end
            
        else
            
            %here we are simply looking for clusters w/o spatial structure
            conn = conndef(ndims(obs_map),'max');
            obs_cls = bwconncomp(obs_map,conn);
            obs_labelmatrix = labelmatrix(obs_cls);
            
            for i = 1:opt.num_iterations
                
                r_tmp = squeeze(r_map(i,:,:));
                r_cls =  bwconncomp(r_tmp,conn);
                if ~isempty(r_cls.PixelIdxList)
                    max_r_cls(i) = max(cellfun(@length,r_cls.PixelIdxList));
                end
            end
            
        end
        
        %now compare observed with random clusters
        obs_lengths = cellfun(@length, obs_cls.PixelIdxList);
        if ~isempty(obs_lengths)
            cluster_pvals = nan(1,length(obs_lengths));
            for i = 1:length(obs_lengths)
                cluster_pvals(i) = (sum(max_r_cls>=obs_lengths(i))+1)/(obs.num_iterations+1);
            end
        end
        
        %save stuff
        stats.clusters = obs_cls.PixelIdxList;
        stats.clustersizes = obs_lengths;
        stats.clusterlabelmatrix = obs_labelmatrix;
        stats.clusterpvals = cluster_pvals;
        stats.randclustermaxdistr = max_r_cls;
        
        
    case {'mixed_of', 'mixed_fo'}
        
        if nd==2, error('Mixed methods of MC correction only work when there are at least 2 dimensions, e.g. space x time, or time x time.'); end;
        
        r_stat = nan([opt.num_iterations sz]); obs_stat = nan(sz);
        
        for i = 1:size(accuracy,2)
            
            for ii = 1:size(accuracy,3)
                
                [r_stat(:,i,ii),obs_stat(i,ii),~] = randomize_accuracy(accuracy(:,i,ii),'num_iterations', opt.num_iterations, 'chance_level', opt.chance_level, 'statistic', opt.statistic);
            end
        end
        
        %if omnibus correction is desired along the last dimension
        if strcmp(opt.method, 'mixed_fo')
            
            r_stat = permute(r_stat, [1 3 2]); obs_stat = permute(obs_stat, [1 3 2]);
        end
        
        max_stat = squeeze(max(r_stat,[],2));
        pval = nan(sz); mask = nan(sz); q = nan(1,size(accuracy,2));
        
        for i = 1:size(accuracy,2)
            
            for ii = 1:size(accuracy,3)
                
                pval(i,ii) = (length(find(max_stat(:,ii)>=obs_stat(i,ii)))+1)/(opt.num_iterations+1);
            end
            
            [q(i), mask(i,:)] = fdr(pval(i,:), opt.alpha); %fdr across 3rd dim
            
        end
        
        if strcmp(opt.method, 'mixed_fo'), mask = mask'; pval = pval'; end %restore dimension order
        
        stats.mask = mask; stats.pval = pval;
        
    otherwise
        
        error('Wrong method for MC correction, see help');
        
end

stats.accuracy = accuracy;
stats.method = opt.method;

end