function T2StarMapGUI(cmdline)
% T2StarMapGUI
%
% Calculates T2* maps from DICOM data in a folder. User will be prompted
% for the folder and echo times (in ms). The T2* map returned is also in
% ms.
%
% T2StarMapGUI(true) to run as commandline only.
%
% Amanda Ng 2013-10-18

    %% Check NIFTI package in path
    chk = which('save_nii');
    if isempty(chk)
        if ~exist('NIFTI','dir')
            error('Cannot locate NIFTI library');
        end
        addpath([pwd '/NIFTI']);
        chk = which('save_nii');
        if isempty(chk)
            error('Error setting path to NIFTI library');
        end
    end

    %% Implement simple command line if display not available
    
    if nargin >= 1 && cmdline || usejava('jvm') && ~feature('ShowFigureWindows')

        fprintf(1, '\n\nT2* Mapping Tool\n');
        fprintf(1, '=============================================\n');
        fprintf(1, 'Press Ctrl+C at any time to cancel\n');
        
        % Prompt user for folder
        folder = [];
        while isempty(folder)
            folder = input('Enter DICOM folder path:', 's');

            % Check folder exists
            if isempty(folder)
                folder = pwd;
            elseif ~exist(folder,'dir')
                fprintf(1,'Folder does not exist.\n');
                folder = [];
            end
        
            % Get DICOM files
            if ~isempty(folder)
                files = dir([folder '/*.dcm']);
                files([files.isdir] == 1) = [];

                if numel(files) == 0
                    fprintf(1,'No DICOM files found in folder.\n');
                    folder = [];
                end
            end
        end

        % Scan files
        for n = 1:length(files)
            files(n).name = [folder '/' files(n).name];
            info = dicominfo(files(n).name);
            files(n).EchoNumber = info.EchoNumber;
            files(n).SliceLocation = info.SliceLocation;
            files(n).data = dicomread(files(n).name);
        end

        % Load data
        idx = sortrows(sortrows([1:n ; files.SliceLocation ; files.EchoNumber]',3),2);
        SliceLocations = sort(unique([files.SliceLocation]));
        data = zeros([size(files(1).data) numel(SliceLocations) numel(max([files.EchoNumber]))]);
        for i = 1:size(idx,1)
            data(:,:,SliceLocations == files(i).SliceLocation,files(i).EchoNumber) = double(files(i).data);
        end    

        % Prompt user for echo times
        TE = [];
        while isempty(TE)
            EchoString = input('Echo times (in ms): ','s');
                
            if ~isempty(EchoString) && evalin('base',...
                    sprintf('exist(''%s'', ''var'') && numel(%s) == %d',EchoString,EchoString, size(data,4)))
                TE = evalin('base', EchoString);
            elseif ~isempty(EchoString)
                TE = str2double(regexp(EchoString, '[ ,]', 'split'));
                TE = TE(~isnan(TE));

                if numel(TE) ~= size(data,4)
                    fprintf(1,'Number of echo times does not match data.\n');
                    TE = [];
                end
            end
        end
        
        % Prompt user for slice numbers
        slices = [];
        while isempty(slices)
            SliceString = input(sprintf('Select slices to process (1-%d): ',size(data,3)),'s');
            if isempty(SliceString)
                fprintf(1,'\b1-%d\n',size(data,3));
                slices = 1:size(data,3);
            else
                try
                    slices = eval(['[' strrep(SliceString,'-',':') ']']);
                    if any(slices < 1) || any(slices > size(data,3))
                        fprintf(1,'Slice numbers must be between 1 and %d', size(data,3));
                        slices = [];
                    end
                catch ME
                    fprintf(1,'Cannot understand slices. Should be of the form "1-3,5"');
                    slices = [];
                end
            end
        end
        
        % Prompt user for echo numbers
        echoes = [];
        while isempty(echoes)
            EchoString = input(sprintf('Select echoes to process (1-%d): ',size(data,4)),'s');
            if isempty(EchoString)
                fprintf(1,'\b1-%d\n',size(data,4));
                echoes = 1:size(data,4);
            else
                try
                    echoes = eval(['[' strrep(EchoString,'-',':') ']']);
                    if any(echoes < 1) || any(echoes > size(data,4))
                        fprintf(1,'Echo numbers must be between 1 and %d', size(data,4));
                        echoes = [];
                    end
                catch ME
                    fprintf(1,'Cannot understand echoes. Should be of the form "1-3,5"');
                    echoes = [];
                end
            end
        end
        
        % Perform T2* mapping
        [t2star S0 rmse] = t2starmap(data(:,:,slices,echoes), TE(echoes));

        % Save T2* map
        filename = [];
        while isempty(filename)
            filename = input('Save T2* map as (eg t2star.nii.gz): ','s');
            if isempty(filename)
                filename = 't2star.nii.gz';
                basename = 't2star';
                ext = '.nii.gz';
            elseif length(filename) < 7
                fprintf(1,'File type must be *.nii or *.nii.gz');
                filename = [];
            elseif strcmp(filename(end-3:end),'.nii') 
                basename = filename(1:end-4);
                ext = '.nii';
            elseif strcmp(filename(end-6:end), '.nii.gz')
                basename = filename(1:end-7);
                ext = '.nii.gz';
            else
                fprintf(1,'File type must be *.nii or *.nii.gz');
                filename = [];
            end
        end
        
        nii = make_nii(t2star, [info.PixelSpacing' info.SliceThickness], ...
            [],[],'T2* map');        
        save_nii(nii, filename);
        
        nii = make_nii(rmse, [info.PixelSpacing' info.SliceThickness], ...
            [],[],'T2* error map');        
        save_nii(nii, [basename '_rmse' ext]);        
        
        % Save T2* map 
        assignin('base','t2star',t2star)
        assignin('base','rmse',rmse)
        assignin('base','data',data);
        assignin('base','TE',TE);
        return
    end

    %% Declare variables
    files = [];
    info = [];
    data = [];
    TE = [];
    slices = [];
    clim = [0 20];
    t2star = [];
    S0 = [];
    rmse = [];
    CalcEchoes = [];

    %% Create GUI
    close
    hFig = figure('Visible', 'off','WindowStyle','normal', ...
        'color',[0.929412 0.929412 0.929412]);
    drawnow
    
    set(hFig,'Units','pixels');
    figpos = get(hFig,'Position');
    figpos(3) = 560;
    figpos(4) = 700;
    %figpos(4) = figpos(3);
    set(hFig,'Position',figpos)
    
    W = figpos(3);
    H = figpos(4);
    
    % Tool Title
    hToolTitle = uicontrol('Style','text', ...
                           'Position', [5 H-20 559 20], ...
                           'String', 'T2* Mapping Tool', ...
                           'FontSize', 16, 'FontWeight', 'bold');
    
	% Close button
    hCloseButton = uicontrol('Style','pushbutton', ...
        'Position', [W-80 H-30 60 22], ...
        'String', 'Close', ...
        'FontSize', 12, ...
        'Callback', @hCloseTool_Callback);
    
    % Select folder
    hDICOMFolderText = uicontrol('Style','text', ...
                                 'Position', [5 H-45 500 15], ...
                                 'string', '1. Select DICOM folder: ', ...
                                 'FontSize', 13, 'FontWeight', 'bold', ...
                                 'Horiz', 'left');
    
    hDICOMFolder = uicontrol('Style','Edit',...
                             'Position', [5 H-70 495 25], ...
                             'String', pwd,'horiz','left','FontSize',12);
                                                  
    hFolderButton = uicontrol('Style','pushbutton', ...
                            'Position', [500 H-70 55 25], ...
                            'String', 'Change', ...
                            'FontSize',12, ...
                            'Callback',@hFolderButton_Callback);

    % Scan folder
    hScanFolderText = uicontrol('Style','text', ...
                                 'Position', [5 H-95 150 15], ...
                                 'string', '2. Scan DICOM folder: ', ...
                                 'FontSize', 13, 'FontWeight', 'bold', ...
                                 'Horiz', 'left');
                             
    hScanButton = uicontrol('Style','pushbutton', ...
                            'Position', [155 H-100 80 25], ...
                            'String', 'Scan folder', ...
                            'FontSize',12, ...
                            'Callback', @hScanButton_Callback);
                        
    % Enter echo times
    hEchoTimesText = uicontrol('Style','text', ...
                                 'Position', [5 H-120 150 15], ...
                                 'Enable', 'off', ...
                                 'string', '3. Enter echo times: ', ...
                                 'FontSize', 13, 'FontWeight', 'bold', ...
                                 'Horiz', 'left');
                             
    hEchoTimes = uicontrol('Style','Edit',...
                                 'Enable', 'off', ...
                             'Position', [155 H-125 345 25], ...
                             'horiz','left','FontSize',12);
                                                  
    hEchoTimesButton = uicontrol('Style','pushbutton', ...
                            'Position', [500 H-125 55 25], ...
                                 'Enable', 'off', ...
                            'String', 'Okay', ...
                            'FontSize',12, ...
                            'Callback', @hEchoTimesButton_Callback);
                        
    % Select slices
    hSlicesText = uicontrol('Style','text', ...
                                 'Position', [5 H-145 150 15], ...
                                 'Enable', 'off', ...
                                 'string', '4. Select slices: ', ...
                                 'FontSize', 13, 'FontWeight', 'bold', ...
                                 'Horiz', 'left');
    
    hSlices = uicontrol('Style','Edit',...
                                 'Enable', 'off', ...
                             'Position', [155 H-150 345 25], ...
                             'horiz','left','FontSize',12);
                                                  
    hSlicesButton = uicontrol('Style','pushbutton', ...
                                 'Enable', 'off', ...
                            'Position', [500 H-150 55 25], ...
                            'String', 'View', ...
                            'FontSize',12, ...
                            'Callback',@hSlicesButton_Callback);
    
    % Select echoes
    hEchoesText = uicontrol('Style','text', ...
                                 'Position', [5 H-170 150 15], ...
                                 'Enable', 'off', ...
                                 'string', '5. Select echoes: ', ...
                                 'FontSize', 13, 'FontWeight', 'bold', ...
                                 'Horiz', 'left');
    
    hEchoes = uicontrol('Style','Edit',...
                             'Position', [155 H-175 345 25], ...
                                 'Enable', 'off', ...
                             'horiz','left','FontSize',12);
                                                  
    hEchoesButton = uicontrol('Style','pushbutton', ...
                            'Position', [500 H-175 55 25], ...
                                 'Enable', 'off', ...
                            'String', 'View', ...
                            'FontSize',12, ...
                            'Callback',@hEchoesButton_Callback);
                        
    % Calculate
    hCalcButton = uicontrol('Style','pushbutton', ...
                            'Position', [W/2-100 H-213 200 35], ...
                            'Enable', 'off', ...
                            'String', 'Calculate T2*', ...
                            'FontSize',14, ...
                            'Callback',@hCalcButton_Callback);
                     
	
    % Display axes
    
    hPanel = uipanel('Units','pixels','Position', [4 4 W-6 H-220],...
        'Visible','off');
    
    hSliceNumberText = uicontrol('Parent', hPanel, ...
        'Style','text', ...
        'Position', [5 H-255 100 25], ...
        'String', 'Viewing slice: ', ...
        'FontSize', 12);
    hSliceNumber = uicontrol('Parent', hPanel, ...
        'Style','popupmenu', ...
        'Position', [105 H-258 75 30], ...
        'String', ' ', ...
        'FontSize', 12, ...
        'Callback', @hSliceNumber_Callback);
    
    hContrastText = uicontrol('Parent', hPanel, ...
        'Style','text', ...
        'Position', [W-175 H-255 60 25], ...
        'String', 'Contrast:', ...
        'FontSize', 12);
    
    hContrastMin = uicontrol('Parent', hPanel, ...
        'Style','edit', ...
        'Position', [W-115 H-250 40 25], ...
        'String', clim(1), ...
        'FontSize', 12, ...
        'Callback', @ChangeContrast);
    
    hContrastToText = uicontrol('Parent', hPanel, ...
        'Style','text', ...
        'Position', [W-75 H-255 20 25], ...
        'String', 'to', ...
        'FontSize', 12);
    
    hContrastMax = uicontrol('Parent', hPanel, ...
        'Style','edit', ...
        'Position', [W-55 H-250 40 25], ...
        'String', clim(2), ...
        'FontSize', 12, ...
        'Callback', @ChangeContrast);
    
    hAxes = axes('Parent', hPanel, ...
        'Units', 'Pixels', 'Position', [10 40 W-30 H-300]);
    axis off

    hAnalyseButton = uicontrol('Parent', hPanel, ...
        'Style','pushbutton', ...
        'Position', [10 10 70 22], ...
        'String', 'Analyse', ...
        'FontSize', 12, ...
        'Callback', @Analyse);
    
    hSaveButton = uicontrol('Parent', hPanel, ...
        'Style','pushbutton', ...
        'Position', [W-80 10 60 22], ...
        'String', 'Save', ...
        'FontSize', 12, ...
        'Callback', @SaveMap);
    
    drawnow
    set(hFig,'Visible','on')
    
    %% OPEN FOLDER DIALOG BOX
    function hFolderButton_Callback(hObject, eventdata, handles)
        folder = uigetdir([],'Select DICOM folder');
        if folder
            set(hDICOMFolder,'String',folder);
        end
    
    end

    %% SCAN DICOM FOLDER
    function hScanButton_Callback(hObject, eventdata, handles)
        
        folder = get(hDICOMFolder, 'String');
        
        % Get DICOM files
        files = dir([folder '/*.dcm']);
        files([files.isdir] == 1) = [];
        
        if numel(files) == 0
            msgbox('No DICOM files found in folder','modal');
            return
        end
        
        for n = 1:length(files)
            files(n).name = [folder '/' files(n).name];
            info = dicominfo(files(n).name);
            files(n).EchoNumber = info.EchoNumber;
            files(n).SliceLocation = info.SliceLocation;
            files(n).data = dicomread(files(n).name);
        end

        % Load data
        idx = sortrows(sortrows([1:n ; files.SliceLocation ; files.EchoNumber]',3),2);
        SliceLocations = sort(unique([files.SliceLocation]));
        data = zeros([size(files(1).data) numel(SliceLocations) numel(max([files.EchoNumber]))]);
        for i = 1:size(idx,1)
            data(:,:,SliceLocations == files(i).SliceLocation,files(i).EchoNumber) = double(files(i).data);
        end    
        
        % Enable echo times
        set([hEchoTimesText hEchoTimes hEchoTimesButton],'Enable','on');
        set(hEchoTimesText,'String',sprintf('3. Enter %d echo times:',size(data,4)));
        
        % Initialise slices
        set(hSlicesText,'String',sprintf('4. Select slices (1-%d):',size(data,3)));
        set(hSlices,'String',sprintf('1-%d',size(data,3)));
        
        % Initialise echoes
        set(hEchoesText,'String',sprintf('5. Select echoes (1-%d):',size(data,4)));
        set(hEchoes,'String',sprintf('1-%d',size(data,4)));
    end

    %% CHECK ECHO TIMES
    function hEchoTimesButton_Callback(hObject, eventdata, handles)
        EchoString = get(hEchoTimes,'String');
        if ~isempty(EchoString) && ~any(EchoString == ' ') && evalin('base',...
                sprintf('exist(''%s'', ''var'') && numel(%s) == %d',EchoString,EchoString, size(data,4)))
            TE = evalin('base', EchoString);
        else
            TE = ParseEchoTimesString(EchoString, true);
            if TE == -1
                return
            end
        end
        
        % Reset string
        s = sprintf('%0.3f, ',TE);
        s = s(1:end-2);
        set(hEchoTimes,'String',s)
        
        % Enable other controls
        set([hSlicesText hSlices hSlicesButton],'Enable','on');
        set([hEchoesText hEchoes hEchoesButton],'Enable','on');
        set(hCalcButton,'Enable','on');
    end

    %% CALCULATE T2*
    function hCalcButton_Callback(hObject, eventdata, handles)
        TE = ParseEchoTimesString(get(hEchoTimes,'String'), true);
        if TE == -1
            return
        end
        
        slices = ParseSliceString(get(hSlices,'String'),true);
        if slices == -1
            return
        end
        
        echoes = ParseEchoString(get(hEchoes,'String'),true);
        if echoes == -1
            return
        end
        
        CalcEchoes = false(size(data,4),1);
        CalcEchoes(echoes) = true;
        
        set(hPanel,'Visible','off');
        set(hCalcButton,'String','Calculating...','Enable','off');
        drawnow
        [t2star S0 rmse] = t2starmap(data(:,:,slices,echoes), TE(echoes));
        set(hPanel,'Visible','on');
        set(hCalcButton,'String','Calculate T2*','Enable','on');
        
        set(hSliceNumber,'String',num2cell(slices'));
        
        set(hPanel,'Visible','on');
        
        DisplayT2star(slices(1));
    end

    %% CHANGE VIEWED SLICE
    function hSliceNumber_Callback(hObject, eventdata, handles)
        n = get(hSliceNumber,'Value');
        slices = str2double(get(hSliceNumber,'String'));
        DisplayT2star(slices(n));
    end

    %% ADJUST CONTRAST
    function ChangeContrast(hObject,eventdata,handles)
        try
            climmin = str2double(get(hContrastMin,'String'));
            if isnan(climmin)
                set(hContrastMin,'String',num2str(clim(1)))
            else
                clim(1) = climmin;
            end
            climmax = str2double(get(hContrastMax,'String'));
            if isnan(climmax)
                set(hContrastMax,'String',num2str(clim(2)))
            else
                clim(2) = climmax;
            end
        catch ME
            msgbox('Contrast values must be numbers','modal')
            return
        end
        set(hAxes,'clim', clim);
    end

    %% DISPLAY T2STAR IMAGE
    function DisplayT2star(slice)
        img = t2star(:,:,slices == slice);
        axes(hAxes)
        imagesc(img,clim);
        set(hAxes, 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatioMode', 'auto');
        axis off
        colorbar
        title ''
    end

    %% PARSE ECHO TIMES STRING
    function TE = ParseEchoTimesString(EchoString,ShowMessage)
        if numel(EchoString) == 0
            if ShowMessage
                msgbox('No echo times listed','modal')
            end
            TE = -1;
            return
        end
        try
            TE = str2double(regexp(EchoString, '[ ,]', 'split'));
            TE = TE(~isnan(TE));
            if numel(TE) ~= size(data,4)
                if ShowMessage
                    msgbox('Incorrect number of echo times','modal')
                end
                TE = -1;
            end
        catch ME
            if ShowMessage
                msgbox('Cannot understand echo times. Should be separated by comma or space."','modal')
            end
            TE = -1;
        end
    end

    %% PARSE SLICES STRING
    function slices = ParseSliceString(SliceString,ShowMessage)
        if numel(SliceString) == 0
            if ShowMessage
                msgbox('No slices listed','modal')
            end
            slices = -1;
            return
        end
        try
            slices = eval(['[' strrep(SliceString,'-',':') ']']);
            if any(slices < 1) || any(slices > size(data,3))
                if ShowMessage
                    msgbox(sprintf('Slice numbers must be between 1 and %d', size(data,3)),'modal')
                end
                slices = -1;
            end
        catch ME
            if ShowMessage
                msgbox('Cannot understand slices. Should be of the form "1-3,5"','modal')
            end
            slices = -1;
        end
     end
        
    %% PARSE ECHO STRING
    function echoes = ParseEchoString(EchoString,ShowMessage)
        if numel(EchoString) == 0
            if ShowMessage
                msgbox('No echoes listed','modal')
            end
            echoes = -1;
            return
        end
        try
            echoes = eval(['[' strrep(EchoString,'-',':') ']']);
            if any(echoes < 1) || any(echoes > size(data,4))
                if ShowMessage
                    msgbox(sprintf('Echo numbers must be between 1 and %d', size(data,4)),'modal')
                end
                echoes = -1;
            end
        catch ME
            if ShowMessage
                msgbox('Cannot understand echoes. Should be of the form "1-3,5"','modal')
            end
            echoes = -1;
        end
    end

    %% CREATE LIST STRING FROM ARRAY
    function s = CreateListString(A)
        s = '';
        for n = 1:length(A)
            if n == 1
                s = sprintf('%d',A(1));
            elseif A(n) == A(n-1)+1 
                if ~strcmp(s(end),'-')
                    s = [s '-'];
                end
                if n == length(A) || A(n+1) ~= A(n)+1
                    s = sprintf('%s%d',s,A(n));
                end
            else
                s = sprintf('%s,%d',s,A(n));
            end
        end
    end

    %% SAVE MAPS
    function SaveMap(hObject, eventdata, handles)
        [filename p] = uiputfile('*.*','Save T2* map as ...', 't2star.nii.gz');
        
        if filename == 0
            return
        end
        
        [~,basename,ext] = fileparts(filename);
        if strcmp(ext, '.gz')
            gz = '.gz';
            [~,basename,ext] = fileparts(basename);
        else
            gz = '';
        end
        if ~strcmp(ext,'.nii')
            msgbox('File type must be *.nii or *.nii.gz','modal');
            return
        end
        ext = [ext gz];
        
%         if strcmp(filename(end-3:end),'.nii')
%             basename = filename(1:end-4);
%             ext = '.nii';
%         elseif strcmp(filename(end-6:end), '.nii.gz')
%             basename = filename(1:end-7);
%             ext = '.nii.gz';
%         else
%             msgbox('File type must be *.nii or *.nii.gz','modal');
%             return
%         end
        
        nii = make_nii(t2star, [info.PixelSpacing' info.SliceThickness], ...
            [],[],'T2* map');
        
        save_nii(nii, [p '/' filename]);
        
        nii = make_nii(rmse, [info.PixelSpacing' info.SliceThickness], ...
            [],[],'T2* error map');
        
        save_nii(nii, [p '/' basename '_rmse' ext]);
        
    end

    %% CLOSE TOOL
    function hCloseTool_Callback(hObject,evendata,handles)
        close(hFig);
    end

    %% SELECT SLICES FIGURE AND FUNCTIONS
    function hSlicesButton_Callback(hObject,eventdata,handles)
        
        % Setup Figure and controls
        hSliceFig = figure('WindowStyle','normal','Units','normalize', ...
            'Position', [0.05 0.05 0.9 0.9], ...
            'color',[0.929412 0.929412 0.929412]);
        set(hSliceFig,'Units','Pixels');
        SFpos = get(hSliceFig,'Position');
        SFW = SFpos(3);
        SFH = SFpos(4);
        
        hSFTitle = uicontrol('Style','text', ...
            'Position', [5 SFH-30 SFW-10 30], ...
            'String', 'Slice selection', ...
            'FontSize', 16, 'FontWeight', 'bold');
        
        hSFSlicesText = uicontrol('Style','text', ...
                                     'Position', [SFW/2-150 SFH-65 100 25], ...
                                     'string', 'Selected slices: ', ...
                                     'FontSize', 13, 'FontWeight', 'bold', ...
                                     'Horiz', 'left');

        hSFSlices = uicontrol('Style','Edit',...
                                 'Position', [SFW/2-50 SFH-60 250 25], ...
                                 'String', get(hSlices,'String'), ...
                                 'horiz','left','FontSize',12);
                             
        hSFSlicesButton = uicontrol('Style','pushbutton', ...
                                'Position', [SFW/2+210 SFH-60 50 25], ...
                                'String', 'Finish', ...
                                'FontSize',12, ...
                                'Callback',@UpdateMainFig);
    
        % Setup subplots
                             
        nSlices = size(data,3);
        nPlots = min(16,nSlices);
        cPlots = ceil(sqrt(nPlots));
        rPlots = ceil(nPlots/cPlots);
        
        [x y] = ndgrid(0:15,-15:15);
        cdata = repmat((abs(y)>abs(x))*0.929412,[1,1,3]);
        hSFUpButton = uicontrol('Units','Pixels',...
            'Position', [SFW*0.4 SFH-105 SFW*0.2 30], ...
            'CData', cdata, ...
            'Enable','off', ...
            'Callback',@Up_Callback);

        hSPPanel = uipanel('Units','Pixels',...
            'Position', [10 50 SFW-20 SFH-165], ...
            'BorderType','none');
        
        [x y] = ndgrid(-15:0,-15:15);
        cdata = repmat((abs(y)>abs(x))*0.929412,[1,1,3]);
        hSFDownButton = uicontrol('Units','Pixels',...
            'Position', [SFW*0.4 10 SFW*0.2 30], ...
            'CData', cdata, ...
            'Enable','off', ...
            'Callback',@Down_Callback);
        
        delete(findobj(gcf,'type','axes'))
        n = 1;
        for r = 1:rPlots
            for c = 0:cPlots-1
                hSubplots(n) = axes('Parent', hSPPanel, ...
                    'OuterPosition', [c/cPlots 1-r/rPlots 1/cPlots 1/rPlots]);
                n = n + 1;
            end
        end
        
        % Initialise slice string
        slices = ParseSliceString(get(hSlices,'String'), false);
        if slices == -1
            set(hSFSlices,'String',sprintf('1-%d',nSlices));
            slices = 1:nSlices;
        end

        ShowingSlices = 1:nPlots;
        DisplaySlices;
        
        % Callback functions
        function ClickAxes(hObject,eventdata,handles)
            % Change selection of axes
            h = get(hObject,'Parent');
            if all(get(h,'XColor') == [1 0 1])
                set(h,'XColor',[0 0 0],'YColor', [0 0 0]);
                slices(slices == get(h,'UserData')) = [];
            else
                set(h,'XColor',[1 0 1],'YColor', [1 0 1]);
                slices = sort([slices get(h,'UserData')]);
            end
            
            % Set slice string
            s = '';
            for n = 1:length(slices)
                if n == 1
                    s = sprintf('%d',slices(1));
                elseif slices(n) == slices(n-1)+1 
                    if ~strcmp(s(end),'-')
                        s = [s '-'];
                    end
                    if n == length(slices) || slices(n+1) ~= slices(n)+1
                        s = sprintf('%s%d',s,slices(n));
                    end
                else
                    s = sprintf('%s,%d',s,slices(n));
                end
            end
            
            set(hSFSlices,'String',s);
            
        end
        
        % Arrow functions
        function Up_Callback(hObject,eventdata,handles)
            if ShowingSlices(1) > 1
                sSlice = max(1,ShowingSlices(1)-rPlots*cPlots);
                eSlice = min(sSlice+rPlots*cPlots-1,nSlices);
                ShowingSlices = sSlice:eSlice;
                nPlots = numel(ShowingSlices);
                DisplaySlices;
            end
        end
        
        function Down_Callback(hObject,eventdata,handles)
            if ShowingSlices(end) < nSlices
                sSlice = ShowingSlices(end)+1;
                eSlice = min(sSlice+rPlots*cPlots-1,nSlices);
                ShowingSlices = sSlice:eSlice;
                nPlots = numel(ShowingSlices);
                DisplaySlices;
            end
        end
        
        % Display slices
        function DisplaySlices()
            for n = 1:nPlots
                axes(hSubplots(n));
                hImg = imagesc(data(:,:,ShowingSlices(n),1));
                set(hImg,'ButtonDownFcn', @ClickAxes);
                set(hSubplots(n), 'DataAspectRatio', [1 1 1], ...
                    'PlotBoxAspectRatioMode', 'auto', ...
                    'xtick',[],'ytick',[],'LineWidth', 3, ...
                    'Visible','on');
                title(sprintf('Slice %d', ShowingSlices(n)))
                if any(slices == ShowingSlices(n))
                    set(hSubplots(n),'XColor',[1 0 1],'YColor', [1 0 1],'UserData',ShowingSlices(n));
                else
                    set(hSubplots(n),'XColor',[0 0 0],'YColor', [0 0 0],'UserData',ShowingSlices(n));
                end
            end            
            for n = n+1:rPlots*cPlots
                cla(hSubplots(n));
                set(hSubplots(n),'Visible','off');
            end
            
            if ShowingSlices(1) == 1
                set(hSFUpButton,'Enable','off');
            else
                set(hSFUpButton,'Enable','on');
            end
            if ShowingSlices(end) == nSlices
                set(hSFDownButton,'Enable','off');
            else
                set(hSFDownButton,'Enable','on');
            end                        
        end
        
        % Update slice string in main figure and close current figure
        function UpdateMainFig(hObject,eventdata,handles)
            set(hSlices,'String',get(hSFSlices,'String'))
            close(hSliceFig)
        end
    end
    
    %% SELECT ECHOES FIGURE AND FUNCTIONS
    function hEchoesButton_Callback(hObject,eventdata,handles)
    
        % Check TE string is valid
        TE = ParseEchoTimesString(get(hEchoTimes,'String'), true);
        if TE == -1
            return
        end        
        
        % Setup figure and controls
        hEchoesFig = figure('WindowStyle','normal','Units','normalize', ...
            'Position', [0.05 0.05 0.9 0.9], ...
            'color',[0.929412 0.929412 0.929412]);
        set(hEchoesFig,'Units','Pixels');
        EFpos = get(hEchoesFig,'Position');
        EFW = EFpos(3);
        EFH = EFpos(4);
        
        hEFTitle = uicontrol('Style','text', ...
            'Position', [5 EFH-30 EFW-10 30], ...
            'String', 'Echo selection', ...
            'FontSize', 16, 'FontWeight', 'bold');
        
        hEFEchoesText = uicontrol('Style','text', ...
                                     'Position', [EFW/2-150 EFH-65 100 25], ...
                                     'string', 'Selected echoes: ', ...
                                     'FontSize', 13, 'FontWeight', 'bold', ...
                                     'Horiz', 'left');

        hEFEchoes = uicontrol('Style','Edit',...
                                 'Position', [EFW/2-50 EFH-60 250 25], ...
                                 'String', get(hEchoes,'String'), ...
                                 'horiz','left','FontSize',12);
                             
        hEFEchoesButton = uicontrol('Style','pushbutton', ...
                                'Position', [EFW/2+210 EFH-60 50 25], ...
                                'String', 'Finish', ...
                                'FontSize',12, ...
                                'Callback',@UpdateMainFig);
    
        % Slice to show
        slices = ParseSliceString(get(hSlices,'String'));
        if slices == -1
            slice = 1;
        else
            slice = slices(1);
        end
                            
        % Plot image
        hEFImg = subplot('Position', [2/3 (EFH-60)/EFH*0.65 0.3 (EFH-60)/EFH*0.3]);
        hImg = imagesc(data(:,:,slice,1));
        set(hImg,'ButtonDownFcn', @ChangeFocus);
        set(hEFImg, 'DataAspectRatio', [1 1 1], ...
            'PlotBoxAspectRatioMode', 'auto', ...
            'xtick',[],'ytick',[],'LineWidth', 3, ...
            'Visible','on');
        title 'Select plot point'
        hMarker = [];
        hold on
        y = ceil(size(data,1)/2);
        x = ceil(size(data,2)/2);
        hMarker = scatter(x,y,70,[1 0 1], '*');

            
        % Plot data points
        hEFPlot = subplot('Position', [0.715 0.1 0.25 (EFH-60)/EFH*0.5]);
        plot(TE,squeeze(data(y,x,slice,:)), '-om')
        xlim([0 TE(end)])
        xlabel 'Echo time (ms)'
        ylabel 'Magnitude'
        
        % Setup subplots
        nEchoes = size(data,4);
        nPlots = nEchoes;
        cPlots = ceil(sqrt(nPlots));
        rPlots = ceil(nPlots/cPlots);
        
        hEFPanel = uipanel('Units','normalized',...
            'Position', [0.01 0.01 0.65 (EFH-60)/EFH-0.05], ...
            'BorderType','none');
        
        n = 1;
        for r = 1:rPlots
            rh = 1-r/rPlots;
            for c = 0:cPlots-1
                hSubplots(n) = axes('Parent',hEFPanel,...
                    'OuterPosition', [c/cPlots rh 1/cPlots 1/rPlots], ...
                    'Visible','on');
                n = n+1;
            end            
        end
        
        % Initialise echo string
        echoes = ParseEchoString(get(hEchoes,'String'), false);
        if echoes == -1
            set(hEFEchoes,'String', sprintf('1-%d',size(data,4)));
            echoes = 1:size(data,4);
        end
        
        % Initialise subplots
        for n = 1:nPlots
            % Display echo image
            axes(hSubplots(n));
            hImg = imagesc(data(:,:,1,n));
            set(hImg,'ButtonDownFcn', @ClickAxes);
            set(hSubplots(n), 'DataAspectRatio', [1 1 1], ...
                'PlotBoxAspectRatioMode', 'auto', ...
                'xtick',[],'ytick',[],'LineWidth', 3, ...
                'Visible','on');
            title(sprintf('Echo %d (%0.3fms)', n, TE(n)))
            
            % Show selection
            if any(echoes == n)
                set(hSubplots(n),'XColor',[1 0 1],'YColor', [1 0 1],'UserData',n);
            else
                set(hSubplots(n),'XColor',[0 0 0],'YColor', [0 0 0],'UserData',n);
            end
        end
        
        for n = nPlots+1:rPlots*cPlots
            set(hSubplots(n),'Visible','off')
        end
        
        % Callback functions
        
        function ChangeString(hObject,eventdata,handles)
            check = ParseEchoString(get(hEFEchoes,'String'),true);
            if ~check
                set(hEFEchoes,'String', CreateListString(echoes));
            else
                echoes = check;
            end
        end
        
        function ClickAxes(hObject,eventdata,handles)
            % Toggle selection
            h = get(hObject,'Parent');
            if all(get(h,'XColor') == [1 0 1])
                set(h,'XColor',[0 0 0],'YColor', [0 0 0]);
                echoes(echoes == get(h,'UserData')) = [];
            else
                set(h,'XColor',[1 0 1],'YColor', [1 0 1]);
                echoes = sort([echoes get(h,'UserData')]);
            end
            
            % Update echo string
            set(hEFEchoes,'String',CreateListString(echoes));
            
            RePlot()
            
        end
        
        % Change plotted voxel
        function ChangeFocus(hObject,eventdata,handles)
            axes(hEFImg);
            cp = get(hEFImg,'CurrentPoint');
            x = ceil(cp(1,1)); y = ceil(cp(1,2));
            if ~isempty(hMarker)
                delete(hMarker);
            end
            hMarker = scatter(x,y,70,[1 0 1], '*');

            RePlot()
        end
        
        function RePlot()
            
            echoes = ParseEchoString(get(hEFEchoes,'String'),false);
            
            axes(hEFPlot); cla; hold on
            pts = squeeze(data(y,x,slice,:));
            if numel(echoes) > 0
                plot(TE(echoes),pts(echoes),'-om')
            end
            if nEchoes - numel(echoes) > 0
                UnselectedEchoes = true(nEchoes,1);
                UnselectedEchoes(echoes) = false;
                scatter(TE(UnselectedEchoes),pts(UnselectedEchoes),20,'o')
            end
            xlim([0 TE(end)])
            xlabel 'Echo time (ms)'
            ylabel 'Magnitude'
        end
        
        % Update echo string in main figure and close this figure
        function UpdateMainFig(hObject,eventdata,handles)
            set(hEchoes,'String',get(hEFEchoes,'String'))
            close(hEchoesFig)
        end
    end

    %% ANALYSE T2STAR MAP
    function Analyse(hObject, eventdata, handles)
        
        % Get slice to analyse
        t2starslice = get(hSliceNumber,'Value');
        slices = str2double(get(hSliceNumber,'String'));
        slice = slices(t2starslice);
        
        % Setup figure
        hAFig = figure('WindowStyle','normal','Units','normalize', ...
            'Position', [0.05 0.05 0.9 0.9], ...
            'color',[0.929412 0.929412 0.929412], ...
            'InvertHardCopy','off');
        drawnow
        set(hAFig,'Units','Points');
        Apos = get(hAFig,'Position');
        set(hAFig,'PaperUnits','Points','PaperPosition',Apos);
        
        set(hAFig,'Units','Pixels');
        Apos = get(hAFig,'Position');
        AW = Apos(3);
        AH = Apos(4);
        
        % Set title
        hATitle = uicontrol('Style','text', ...
            'Position', [5 AH-40 AW-10 30], ...
            'String', sprintf('Analyse T2* Map (slice %d)',slice), ...
            'FontSize', 16, 'FontWeight', 'bold');
        
        SPh = ((AH-50)/AH - 0.1)/2;
        
        % T2star sub plot
        hAT2star = subplot('Position', [0.05 SPh+0.05 0.45 SPh-0.05]);
        img = t2star(:,:,t2starslice);
        hT2starImg = imagesc(img,clim);
        set(hAT2star, 'DataAspectRatio', [1 1 1], ...
            'PlotBoxAspectRatioMode', 'auto', ...
            'ButtonDownFcn', '');
        set(hT2starImg,'ButtonDownFcn',@ChangeFocus);
        axis off
        colorbar
        hold on
        title('T2* Map','FontSize', 14);
        
        % RMS error sub plot
        hARMSE = subplot('Position', [0.05 0.05 0.45 SPh-0.05]);
        img = rmse(:,:,t2starslice);
        hRMSEImg = imagesc(img);
        set(hARMSE, 'DataAspectRatio', [1 1 1], 'PlotBoxAspectRatioMode', 'auto');
        set(hRMSEImg,'ButtonDownFcn',@ChangeFocus);
        axis off
        colorbar
        hold on
        title('T2* Map error (RMS)','FontSize', 14)
        
        % Statistics panel
        hAStatsPanel = uipanel('Title','Statistics', ...
            'Units','normalized', ...
            'Position', [0.55 SPh*2*0.8 0.4 SPh*2*0.2], ...
            'FontSize', 14);
        
        hAStats = uicontrol('Parent', hAStatsPanel, ...
            'Style','text', ...
            'Units','normalized', ...
            'Position', [0.05 0.05 0.9 0.9], ...
            'FontSize', 12, ...
            'FontName','Courier', ...
            'HorizontalAlignment', 'left');
        
        % Fit plot
        hAPlot = subplot('Position', [0.6 0.1 0.35 SPh*2*0.75-0.1]);
        ylabel('Magnitude','FontSize',12);
        xlabel('Echo Time (ms)','FontSize',12);
        
        % Controls
        hAButtonGroup = uibuttongroup('Title', 'Show statistics about', ...
            'Units','Pixels', ...
            'Position', [AW*0.05 AH-90 200 50], ...
            'FontSize', 14, ...
            'SelectionChangeFcn', @hButtonGroup_Callback);
        hAVoxelRadio = uicontrol('Style', 'radio', ...
            'Parent', hAButtonGroup, ...
            'Units', 'normalized', ...
            'Position', [0.05 0.05 0.45 0.9], ...
            'String', 'Voxel', ...
            'FontSize', 12, ...
            'Value', 1);
        hARegionRadio = uicontrol('Style', 'radio', ...
            'Parent', hAButtonGroup, ...
            'Units', 'normalized', ...
            'Position', [0.5 0.05 0.45 0.9], ...
            'String', 'Region', ...
            'FontSize', 12, ...
            'Value', 0);     
        
        hAInstructions = uicontrol('Style','text', ...
            'Units','Pixels', ...
            'Position', [AW*0.05+250 AH-90 (AW*0.95-250)*0.8 50], ...
            'String', 'Click in the T2* Map to inspect voxel statistics', ...
            'FontSize', 12, ...
            'HorizontalAlignment', 'left');
        
        hASaveButton = uicontrol('Style', 'pushbutton', ...
            'Units','Pixels', ...
            'Position', [AW-250 AH-80 120 30], ...
            'String', 'Save Screen', ...
            'FontSize', 14,...
            'Callback', @SaveScreen);
                
        hACloseButton = uicontrol('Style', 'pushbutton', ...
            'Units','Pixels', ...
            'Position', [AW-120 AH-80 60 30], ...
            'String', 'Close', ...
            'FontSize', 14,...
            'Callback', @CloseFig);
                
        hAROI = -1;
        ROIid = [];
        ROI = false(size(t2star(:,:,1)));
        
        % Initalise values
        x = ceil(size(t2star, 2)/2);
        y = ceil(size(t2star, 1)/2);
        
        axes(hAT2star);
        hAPt = [-1 -1];
        
        CalcStats;
        
        % Callback functions
        function hButtonGroup_Callback(hObject, eventdata, handles)
            if get(hAVoxelRadio,'Value')
                if isstruct(ROIid)
                    removeNewPositionCallback(hAROI,ROIid);
                    ROIid = [];
                end
                if hAROI ~= -1
                    delete(hAROI);
                    hAROI = -1;
                end
                
                set(hAInstructions,'String', 'Click in the T2* Map to inspect voxel statistics');
                            
                x = ceil(size(t2star, 2)/2);
                y = ceil(size(t2star, 1)/2);
                CalcStats;
            else
                if hAPt(1) ~= -1
                    delete(hAPt(1));
                end
                if hAPt(2) ~= -1
                    delete(hAPt(2));
                end
                hAPt = [-1 -1];
                
                set(hAInstructions,'String', 'Click in the T2* Map to create an ROI.');
                set(hAStats,'String', '');
                
                cla(hAPlot);
                xlabel T2*
                ylabel 'Number of voxels'
                set(hAPlot,'xlimmode','auto');
                legend hide
                hAROI = impoly(hAT2star);
                s = {'Press A and click on a line to create a new vertex.';
                     'Right-click a vertex to edit/delete.'};
                set(hAInstructions,'String', s);
                ROIid = addNewPositionCallback(hAROI,@(x) CalcStats);
                CalcStats;
            end
        end
        
        % Change focus for points
        function ChangeFocus(hObject, eventdata, handles)
            cp = get(get(hObject,'Parent'),'CurrentPoint');
            x = ceil(cp(1,1));
            y = ceil(cp(1,2));
            
            CalcStats;
        end
        
        % Calculate statistics and update plots
        function CalcStats()

            if get(hAVoxelRadio,'Value')
                axes(hAT2star);
                if hAPt(1) ~= -1
                    delete(hAPt(1));
                end
                hAPt(1) = scatter(x,y,100,'*m');
                
                axes(hARMSE);
                if hAPt(2) ~= -1
                    delete(hAPt(2));
                end
                hAPt(2) = scatter(x,y,100,'*m');                
            
                s = sprintf('Current point: x=%d y=%d\n',x,y);
                s = [s sprintf('   T2* = %0.3f\n', t2star(y,x,t2starslice))];
                s = [s sprintf('   RMS error = %0.3f\n', rmse(y,x,t2starslice))];
                set(hAStats,'String', s);
                
                axes(hAPlot); cla; hold on
                plot(TE(CalcEchoes),squeeze(data(y,x,slice,CalcEchoes)), ...
                    '-mo','DisplayName','data');
                xlim([0 TE(end)]);
                plot(TE, S0(y,x,t2starslice).*exp(-TE./t2star(y,x,t2starslice)), ...
                    '-b','DisplayName','fit');    
                legend show
                ylabel('Magnitude','FontSize',12);
                xlabel('Echo Time (ms)','FontSize',12);
            else
                ROI = createMask(hAROI);
                
                s = sprintf('ROI: %d voxels\n',sum(ROI(:)));
                tmp = t2star(:,:,t2starslice);                
                s = [s sprintf('   T2* mean = %0.3f\n', mean(tmp(ROI)))];
                s = [s sprintf('       variance = %0.3f\n', std(tmp(ROI))^2)];
                tmp = rmse(:,:,t2starslice);
                s = [s sprintf('   Mean RMS error = %0.3f\n', mean(tmp(ROI)))];
                set(hAStats,'String', s);
                
                axes(hAPlot); cla; hold on
                hist(tmp(ROI),ceil(sqrt(sum(ROI(:)))));
                xlabel('T2*','FontSize',12);
                ylabel('Number of voxels','FontSize',12);
            end
        end
        
        function SaveScreen(hObject,events,handles)
            [filename p] = uiputfile('screen.tif');
            
            if ~filename
                return
            end
            
            h = [findobj(hAButtonGroup); hAInstructions; hASaveButton; hACloseButton];
            s = get(hAButtonGroup,'Title');
            
            set(h,'Visible','off');
            set(hAButtonGroup,'Title','');
            saveas(hAFig,[p '/' filename]);
            set(h,'Visible','on');
            set(hAButtonGroup,'Title',s);
            
        end
        
        function CloseFig(hObject,events,handles)
            close(hAFig);
        end
        
    end

end
