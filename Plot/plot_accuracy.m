function [ ] = plot_accuracy( accuracy, errorbar, varargin )
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here
p = inputParser;
addParameter(p, 'time',[]);
addParameter(p, 'color', 'k');
addParameter(p, 'signif', []);
addParameter(p, 'smooth', 1);
addParameter(p, 'ylim', [40 100]);
addParameter(p, 'ylabel', 'Accuracy (%)');
addParameter(p, 'xlabel', 'Time (s)');
parse(p, varargin{:});

if isempty(p.Results.time)
    time = 1:length(accuracy);
end;
    
if length(time)~=size(errorbar,2) || length(accuracy)~=size(errorbar,2)
    error('Time, accuracy and error should have the same length');
end;

if size(errorbar,1)==1
    upper = accuracy + errorbar;
    lower = accuracy - errorbar;
elseif size(errorbar,1)==2
    if errorbar(1,1)>errorbar(2,1)
         errorbar = flipud(errorbar);
    end;
    upper = errorbar(2,:);
    lower = errorbar(1,:);
else
    error('The errorbar can contain one or two row vectors');
end;

patch([time fliplr(time)], [smooth(upper, p.Results.smooth)' fliplr(smooth(lower, p.Results.smooth)')], p.Results.color, 'EdgeColor', 'none');
alpha 0.15; hold on; 
line([time(1) time(end)], [50 50]); hold on;
plot(time, accuracy, p.Results.color); hold on;

if ~isempty(p.Results.signif)
    for j = 1:size(p.Results.signif,1)
        line([p.Results.signif(j,1) p.Results.signif(j,2)], p.Results.ylim+5, 'color', p.Results.color, 'LineWidth', 2); hold on;
    end;
    line([p.Results.signif(1,1) p.Results.signif(1,1)], p.Results.ylim, 'color', p.Results.color); hold on;
end;

ylim(p.Results.ylim);
xlim([time(1) time(end)]);
ylabel(p.Results.ylabel);
xlabel(p.Results.xlabel);
box off;

end

