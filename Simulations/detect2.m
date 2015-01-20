% Load raw data.
rawData = importdata('rawData.txt');
% rawData = rawData(40000:90000-1);
rawDataCount = size(rawData,1);

% Perform fft.
rawDataFFT = fft(rawData);

% Compute the ultra sounds frequencies used by AirNFC.
minimumOscillationCount = 789;
carrierCount = 100;
oscillationPeriod = 2048;
minimumFrequency = ceil(minimumOscillationCount * rawDataCount / oscillationPeriod);
maximumFrequency = floor((minimumOscillationCount+carrierCount-1) * rawDataCount / oscillationPeriod);

% Let only interesting frequencies pass.
rawDataFFT(1:minimumFrequency) = 0;
rawDataFFT(1+maximumFrequency+1:size(rawDataFFT,1)) = 0;

% Perform inverse FFT.
filteredData = ifft(rawDataFFT, 'symmetric');

% Compute correlation
symbolSize = 256;
subsymbolSize = symbolSize / 2;
correlations = zeros(size(rawData));
maxCorrelation = 0;
for signalStart=1:rawDataCount-symbolSize+1
    v1 = filteredData(signalStart:signalStart+subsymbolSize-1);
    v2 = flipud(filteredData(signalStart+subsymbolSize:signalStart+symbolSize-1));
    % Normalize the 2 vectors.
%     v1 = v1/norm(v1);
%     v2 = v2/norm(v2);
    % Compute the scalar product of the 2 vectors.
    correlations(signalStart) = (v1' * v2) / norm(v1 - v2);
    if correlations(signalStart) > maxCorrelation
        maxCorrelation = correlations(signalStart)
        signalStart
    end
end

figure;
plot(correlations);hold all;plot(filteredData);hold off;figure(gcf);