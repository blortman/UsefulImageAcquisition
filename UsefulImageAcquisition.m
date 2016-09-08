classdef UsefulImageAcquisition < handle
    properties
        Adapter = 'gige';
        Mode = 'Mono12';
        NumberOfHistogramBins = 128;
        ImageData;
    end
    
    properties
        videoInputObject;
        videoInputSource;
        cameraResolution;
        mainFigure;
        videoPreviewAxesHandle;
        videoPreviewImageHandle;
        histogramAxesHandle;
        imageStatisticsAxesHandle;
        startPreviewPushbuttonHandle;
        stopPreviewPushbuttonHandle;
        roiStatusEditHandle;
        roiPushbuttonHandle;
        fullroiPushbuttonHandle;
        stretchContrastCheckboxHandle;
        exposureEditHandle;
        gainEditHandle;
        acquirePushbuttonHandle;
        frameRateEditHandle;
    end
    
    properties
        acquisitionPhase = 0;
        acquisitionTime;
    end
    
    properties ( Dependent )
        FrameRate;
    end
    
    methods
        function delete( this )
            this.Close();
        end

        function Close( this )
            this.StopPreview();
            delete( this.videoInputObject );
            delete( this.mainFigure );            
        end
        
        function Initialize( this )
            
            if( ~isempty( this.videoInputObject ) )
                if( isvalid( this.videoInputObject) )
                    return
                end
            end
            
            % create video input object
            this.videoInputObject = videoinput( this.Adapter, 1, this.Mode );
            this.videoInputSource = getselectedsource( this.videoInputObject );
            
            this.videoInputObject.FramesPerTrigger = 1;
            this.cameraResolution = fliplr( this.videoInputObject.VideoResolution );

            % create the main figure
            screenSize = get( 0, 'ScreenSize' );
            this.mainFigure = figure( 'Units', 'pixels' );
            this.mainFigure.Position = [ 50, screenSize(4) - this.cameraResolution(1) - 200, this.cameraResolution(2:-1:1) + [ 300 20 ] ];

            % set up preview and histogram axes
            initialImage = repmat( (1:this.cameraResolution(2) - 1) / (this.cameraResolution(2) - 1), [ this.cameraResolution(1), 1 ] );
            initialImage = insertText( ...
                initialImage, fliplr( this.cameraResolution ) / 2, ...
                'Press Start Preview to start live video', ...
                'AnchorPoint', 'center', 'BoxColor', [ 0 0 0 ], 'TextColor', [1 1 1 ], 'BoxOpacity', 0, 'FontSize', 20 );
            initialImage = uint8( 255 * initialImage(:, :, 1) );
            this.videoPreviewAxesHandle = axes( 'Units', 'pixels', 'Position', [ 10 10 fliplr( this.cameraResolution ) ] );
            this.videoPreviewImageHandle = imshow( initialImage, 'Parent', this.videoPreviewAxesHandle );
            this.DisplayPreviewImage( initialImage );
            setappdata( this.videoPreviewImageHandle, 'UpdatePreviewWindowFcn' , @(obj, event, hImage) this.UpdateLiveDisplay( obj, event, hImage) );
            
            this.histogramAxesHandle = axes( 'Units', 'pixels', 'Position', [ this.cameraResolution(2) + 60, this.cameraResolution(1) - 80, 220 60 ] );
            this.imageStatisticsAxesHandle = axes( 'Units', 'pixels', 'Position', [ this.cameraResolution(2) + 60, this.cameraResolution(1) - 160, 220 20 ] );
            this.UpdateHistogram( initialImage );
            
            % set up UI controls
            
            % start and stop preview buttons
            uiPanelPosition = [ this.cameraResolution(2) + 40, this.cameraResolution(1) - 170 ];
            
            this.startPreviewPushbuttonHandle = this.CreatePushButton( uiPanelPosition + [ 20 0 ], 'Start Preview', @( Source, EventData ) this.HandleStartStopPreviewPushbutton( Source, EventData ) );
            stopPreviewButtonPosition = uiPanelPosition + [this.startPreviewPushbuttonHandle.Position(3) 0 ];
            this.stopPreviewPushbuttonHandle = this.CreatePushButton( stopPreviewButtonPosition, 'Stop Preview', @( Source, EventData ) this.HandleStartStopPreviewPushbutton( Source, EventData ) );
            this.stopPreviewPushbuttonHandle.Position(1) = uiPanelPosition(1) + this.histogramAxesHandle.Position(3) - this.stopPreviewPushbuttonHandle.Position(3);
            
            uiPanelPosition = uiPanelPosition - [ 0 30 ];
            this.roiStatusEditHandle = this.CreateStaticTextBox( ...
                uiPanelPosition, ...
                [ 'ROI: ', num2str( this.videoInputObject.ROIPosition ) ] );
            
            % ROI buttons
            uiPanelPosition = uiPanelPosition - [ 0 30 ];
            this.roiPushbuttonHandle = this.CreatePushButton( uiPanelPosition + [ 20 0 ], 'Select ROI', @( Source, EventData ) this.HandleRoiPushbutton( Source, EventData ) );
            fullRoiButtonPosition = uiPanelPosition + [ this.roiPushbuttonHandle.Position(3) 0 ];
            this.fullroiPushbuttonHandle = this.CreatePushButton( fullRoiButtonPosition, 'Full ROI', @( Source, EventData ) this.HandleFullRoiPushbutton( Source, EventData ) );
            this.fullroiPushbuttonHandle.Position(1) = uiPanelPosition(1) + this.histogramAxesHandle.Position(3) - this.fullroiPushbuttonHandle.Position(3);
            
            uiPanelPosition = uiPanelPosition - [ 0 30 ];
            [ this.stretchContrastCheckboxHandle ] = this.CreateCheckbox( ...
                uiPanelPosition, 'Stretch Contrast', @( Source, EventData ) [] );
            
            %exposure
            uiPanelPosition = uiPanelPosition - [ 0 40 ];
            [ ~, this.exposureEditHandle ] = this.CreateLabelEditTextBox( ...
                uiPanelPosition, ...
                'Exposure (microseconds):', num2str( this.videoInputSource.ExposureTimeAbs ), ...
                @( Source, EventData ) this.HandleExposureEditUpdate( Source, EventData )  );
            
            % gain
            uiPanelPosition = uiPanelPosition - [ 0 30 ];
            this.videoInputSource.Gain = 0;
            [ ~, this.gainEditHandle ] = this.CreateLabelEditTextBox( ...
                uiPanelPosition, ...
                'Gain (0-24):', num2str( this.videoInputSource.Gain ), ...
                @( Source, EventData ) this.HandleGainEditUpdate( Source, EventData )  );            
            
            % frame rate
            uiPanelPosition = uiPanelPosition - [ 0 30 ];
            this.videoInputSource.AcquisitionFrameRateAbs = 20;
            [ ~, this.frameRateEditHandle ] = this.CreateLabelEditTextBox( ...
                uiPanelPosition, ...
                'Frame Rate:', num2str( this.videoInputSource.AcquisitionFrameRateAbs ), ...
                @( Source, EventData ) this.HandleFramesRateEditUpdate( Source, EventData )  );
            
            % frames to acquire
            uiPanelPosition = uiPanelPosition - [ 0 30 ];
            [ ~, this.gainEditHandle ] = this.CreateLabelEditTextBox( ...
                uiPanelPosition, ...
                'Number of Frames:', num2str( this.videoInputObject.FramesPerTrigger ), ...
                @( Source, EventData ) this.HandleFramesToAcquireEditUpdate( Source, EventData )  );
            
            % acquire button
            this.acquirePushbuttonHandle = this.CreatePushButton( ...
                uiPanelPosition + [ 175 0 ], 'Acquire', @( Source, EventData ) this.HandleAcquirePushbutton( Source, EventData ) );
            tic;
        end
        
        function HandleStartStopPreviewPushbutton( this, Source, EventData )
            if( strcmp( Source.String, 'Start Preview' ) )
                this.HandleGainEditUpdate( this.gainEditHandle, [] );
                this.StartPreview(  );
            else
                this.StopPreview(  );
            end
        end
        
        function StartPreview( this )
            this.Initialize();
            preview( this.videoInputObject, this.videoPreviewImageHandle );           
        end
        
        function StopPreview( this )
            this.Initialize();
            stoppreview( this.videoInputObject );
        end
        
        function HandleExposureEditUpdate( this, Source, EventData )
            value = round( str2double( Source.String ) );
            value = max( 0, value );
            value = min( 6e6, value );
            this.videoInputSource.ExposureTimeAbs = value;
            Source.String = num2str( this.videoInputSource.ExposureTimeAbs );
            this.UpdateStatus(  );
        end
        
        function HandleFramesRateEditUpdate( this, Source, EventData )
            value = str2double( Source.String );
            value = max( 0, value );
            value = min( 80, value );
            this.videoInputSource.AcquisitionFrameRateAbs = value;
            Source.String = num2str( this.videoInputSource.AcquisitionFrameRateAbs );
            this.UpdateStatus(  );
        end        
        
        function HandleGainEditUpdate( this, Source, EventData )
            value = round( str2double( Source.String ) );
            value = max( 0, value );
            value = min( 24, value );
            this.videoInputSource.Gain = value;
            Source.String = num2str( this.videoInputSource.Gain );
        end
        
        function HandleFramesToAcquireEditUpdate( this, Source, EventData )
            value = round( str2double( Source.String ) );
            value = max( 0, value );
            this.videoInputObject.FramesPerTrigger = value;
            Source.String = num2str( this.videoInputObject.FramesPerTrigger );
        end
        
        function HandleAcquirePushbutton( this, Source, EventData )
            this.StopPreview(  );
            this.UpdateStatus(  );
            acquiringImage = insertText( ...
                0.5 * ones( this.cameraResolution ), fliplr( this.cameraResolution ) / 2, ...
                [ 'Acquiring ' num2str( this.videoInputObject.FramesPerTrigger ) ' frames' ], ...
                'AnchorPoint', 'center', 'BoxColor', [ 0 0 0 ], 'TextColor', [1 1 1 ], 'BoxOpacity', 0, 'FontSize', 20 );
            this.videoPreviewImageHandle.CData = uint8( 255 * acquiringImage );

            this.AcquireFrames(  );
            thumbnailImage = uint8( zeros( this.cameraResolution ) );
            for ii = 1:min( 9, size( this.ImageData, 4 ) )
                thumb = imresize( this.ImageData(:, :, 1, max( 1, round( ii / size( this.ImageData, 4 ) ) ) ) / 16, floor( ( this.cameraResolution ) ) / 3 );
                [ y, x ] = ind2sub( [ 3 3 ], ii );
                xRange = ( x - 1 ) * size( thumb, 2 ) + 1;
                yRange = ( y - 1 ) * size( thumb, 1 ) + 1;
                thumbnailImage( yRange:(yRange + size( thumb, 1 ) - 1 ), xRange:(xRange + size( thumb, 2 ) - 1) ) = thumb;
            end
            thumbnailImage = repmat( double( this.StretchContrast( thumbnailImage ) ) / 255, [ 1 1 3 ] );
            thumbnailImage = insertText( ...
                thumbnailImage,  fliplr( this.cameraResolution ) / 2, ...
                'Results available in the ''ImageData'' property of this instance', ...
                'AnchorPoint', 'center', 'BoxColor', [ 0 0 0 ], 'TextColor', [1 1 1 ], 'BoxOpacity', 0.5, 'FontSize', 18 );
            this.videoPreviewImageHandle.CData = uint8( 255 * thumbnailImage );
        end
        
        function AcquireFrames( this )
            this.videoInputObject.Timeout = max( this.videoInputSource.ExposureTimeAbs / 1e6, 1 / this.FrameRate ) * this.videoInputObject.FramesPerTrigger * 1.5;
            start( this.videoInputObject );
            this.ImageData = getdata( this.videoInputObject );
        end
        
        function HandleRoiPushbutton( this, Source, EventData )
            this.roiPushbuttonHandle.Enable = 'off';
            this.StopPreview();
            currentImage = double( this.videoPreviewImageHandle.CData ) / 255;
            thumbnailImage = insertText( ...
                currentImage,  [ this.cameraResolution(2) / 2, 30 ], ...
                'Drag a rectangle to select ROI', ...
                'AnchorPoint', 'center', 'BoxColor', [ 0 0 0 ], 'TextColor', [1 1 1 ], 'BoxOpacity', 0.5, 'FontSize', 18 );
            this.DisplayPreviewImage( thumbnailImage );
            selectedRectangle = getrect( this.videoPreviewAxesHandle );
            thumbnailImage = insertText( ...
                thumbnailImage,  [ this.cameraResolution(2) / 2, 30 ] + [ 0 40 ], ...
                [ 'Selected ROI is ' num2str( selectedRectangle ) ' ... hang on a sec.' ], ...
                'AnchorPoint', 'center', 'BoxColor', [ 0 0 0 ], 'TextColor', [1 1 1 ], 'BoxOpacity', 0.5, 'FontSize', 16 );
            this.DisplayPreviewImage( thumbnailImage );
            drawnow;
            this.SetCameraProperty( 'ROIPosition', selectedRectangle );
            this.StartPreview();
        end
        
        function HandleFullRoiPushbutton( this, Source, EventData )
            this.StopPreview();
            this.roiPushbuttonHandle.Enable = 'on';
            this.videoInputObject.ROIPosition = [ 0 0 fliplr( this.cameraResolution ) ];
            this.StartPreview();
        end
        
        function ActualValue = SetCameraProperty( this, PropertyName, Value )
            this.videoInputObject.(PropertyName) = Value;
            
            if( nargout > 0 )
                ActualValue = this.videoInputObject.(PropertyName);
            else
                ActualValue = [];
            end
        end
        
        function UpdateHistogram( this, ImageData )
            [ counts, bins ] = imhist( ImageData, this.NumberOfHistogramBins );
            bins = bins / 255 * 4095;
            
            axes( this.histogramAxesHandle );
            semilogy( bins, counts, 'LineWidth', 2, 'Color', [0 0 1] );
            
            % add a red 'x' if there are any oversaturated pixels
            if( counts(end) > 0 )
                hold on;
                semilogy( bins(end), counts(end), 'rx', 'LineWidth', 2, 'Parent', this.histogramAxesHandle );
                hold off;
            end
            axis( [ 0 4095 1 10^ceil(log10(numel( ImageData ) ) ) ] );

            xlabel( 'Pixel Value', 'Parent', this.histogramAxesHandle, 'FontSize', 7 );
            ylabel( 'Counts', 'Parent', this.histogramAxesHandle, 'FontSize', 7 );
            title( 'Histogram', 'Parent', this.histogramAxesHandle );
            
            meanPixelValue = double( mean( ImageData(:) ) ) / 255 * 4095;
            minimumPixelValue = double( min( ImageData(:) ) ) / 255 * 4095;
            maximumPixelValue = double( max( ImageData(:) ) ) / 255 * 4095;
            pixelStanardDeviation = std( double( ImageData(:) ) ) / 255 * 4095;

            imageStatisticsString = sprintf( '\\mu=%5.0f \\sigma=%5.0f range=[%5.0f, %5.0f]', meanPixelValue, pixelStanardDeviation, minimumPixelValue, maximumPixelValue );
            title( imageStatisticsString, 'Parent', this.imageStatisticsAxesHandle, 'FontSize', 9, 'FontWeight', 'normal' );
            axis( this.imageStatisticsAxesHandle, 'off' ); 
        end
        
        function UpdateLiveDisplay( this, obj, event, hImage)
            this.DisplayPreviewImage( event.Data, this.stretchContrastCheckboxHandle.Value );
            this.UpdateHistogram( event.Data );
            this.UpdateStatus();

            drawnow
        end
        
        function UpdateStatus( this )
            this.roiStatusEditHandle.String = [ 'ROI: ' num2str( this.videoInputObject.ROIPosition ) ];
            if( str2double( this.frameRateEditHandle.String ) > 1e6 / str2double( this.exposureEditHandle.String ) ) 
                this.frameRateEditHandle.ForegroundColor = [ 1 0 0 ];
            else
                this.frameRateEditHandle.ForegroundColor = [ 0 0 0 ];
            end
        end
                
        function DisplayPreviewImage( this, ImageData, StretchContrast )
            if( nargin < 3 )
                StretchContrast = false;
            end
            
            sizeOfImageData = size( ImageData );
            imageSize = sizeOfImageData(1:2);
            if( length( sizeOfImageData ) == 2 )
                numberOfImagePlanes = 1;
            else
                numberOfImagePlanes = sizeOfImageData(3);
            end
            
            if( StretchContrast )
                ImageData = this.StretchContrast( ImageData );
            end
            
            if( imageSize ~= this.cameraResolution )
               magnification = min( this.cameraResolution ./ size( ImageData ) );
               ImageData = imresize( ImageData, magnification ); 
                sizeOfImageData = size( ImageData );
                imageSize = sizeOfImageData(1:2);
            end
            
            if( isa( ImageData, 'double' ) )
                ImageData = uint8( 255 * ImageData );
            end
            
            if( numberOfImagePlanes == 1 )
                ImageData = repmat( ImageData, [ 1 1 3 ] );
            end
            
            if( imageSize == this.cameraResolution )
                this.videoPreviewImageHandle.CData = ImageData;
            else
                paddedImageData = padarray( ...
                    ImageData, ...
                    [floor((this.cameraResolution(1)-imageSize(1))/2) floor((this.cameraResolution(2)-imageSize(2))/2) ], ...
                    64, 'post');
                paddedImageData = padarray( ...
                    paddedImageData, ...
                    [ceil((this.cameraResolution(1)-imageSize(1))/2) ceil((this.cameraResolution(2)-imageSize(2))/2) ], ...
                    64, 'pre');
                this.videoPreviewImageHandle.CData = paddedImageData;
            end
        end
        
        function [ StaticTextHandle, EditTextHandle ] = CreateLabelEditTextBox( this, Position, StaticText, EditText, CallbackFunctionHandle )
            StaticTextHandle = uicontrol( ...
                'Style', 'text', ...
                'String', StaticText , ...
                'Position', [ Position 200 200 ] );
            staticTextUpdatedPosition = [ StaticTextHandle.Position(1:2) StaticTextHandle.Extent(3:4) ];
            StaticTextHandle.Position = staticTextUpdatedPosition;

            editTextPosition = [ sum( staticTextUpdatedPosition(1:2:3) ) staticTextUpdatedPosition(2) 75 20 ];
            EditTextHandle = uicontrol( ...
                'Style', 'edit', ...
                'String', EditText, ...
                'Position', editTextPosition, ...
                'Callback', {CallbackFunctionHandle} );
           
        end
        
        function StaticTextHandle = CreateStaticTextBox( this, Position, StaticText )
            StaticTextHandle = uicontrol( ...
                'Style', 'text', ...
                'String', StaticText , ...
                'Position', [ Position 200 200 ] );
            staticTextUpdatedPosition = [ StaticTextHandle.Position(1:2) StaticTextHandle.Extent(3:4) ] + [ 0 0 50 0 ];
            StaticTextHandle.Position = staticTextUpdatedPosition;
        end
        
        function [ checkboxHandle ] = CreateCheckbox( this, Position, StaticText, CallbackFunctionHandle )
            checkboxHandle = uicontrol( ...
                'Style', 'checkbox', ...
                'String', StaticText, ...
                'Selected', 'off', ...
                'Position', [ Position 100 20 ], ...
                'Callback', {CallbackFunctionHandle} );
%            checkboxHandle.Position = [ checkboxHandle.Position(1:2) checkboxHandle.Extent(3:4) ];
          
        end
        
        function [ PushButtonHandle ] = CreatePushButton( this, Position, ButtonText, CallbackHandle )
            PushButtonHandle = uicontrol( ...
                'Style', 'pushbutton', ...
                'String', ButtonText, ...
                'Position', [ Position 80 20 ], ...
                'Callback', CallbackHandle );
        end

        function Utility( this )
            foo = [];
        end
        
        %% accessors and setters
        
        function set.FrameRate( this, Value )
            this.videoInputSource.AcquisitionFrameRateAbs = Value;
        end
        
        function Value = get.FrameRate( this )
            Value = this.videoInputSource.AcquisitionFrameRateAbs;
        end
    end
    
    methods ( Static )
        function StretchedImage = StretchContrast( InputImage )
            if( isa( InputImage , 'uint8' ) )
                StretchedImage = uint8( 255 * double ( InputImage - min( InputImage(:) ) ) / double( range( InputImage(:) ) ) );
                return;
            end
            if( isa( InputImage , 'uint16' ) )
                StretchedImage = uint16( 65535 * double ( InputImage - min( InputImage(:) ) ) / double( range( InputImage(:) ) ) );
                return;
            end
            if( isa( InputImage , 'double' ) )
                StretchedImage = InputImage - min( InputImage(:) ) / range( InputImage(:) );
                return;
            end
        end
    end
end

% vid.ROIPosition = [217 128 283 206];