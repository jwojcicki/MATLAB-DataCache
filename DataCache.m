% DataCache a singleton class for file caching in program memory for faster
% data access. 
%
% DESCRIPTION:
%
%   DataCache allows using different methods for file reading/conversion and
%   retains in cache only the final output. Cache hit/miss is evaluated based
%   on full qualified path and file timestamp, so if data in the file was
%   updated, the file is going to be re-read.
%
%   Typical use case is to cache data from disk files if you expect to
%   reread data often in our script (e.g. running many times) or across
%   many scripts. When loading a file the DataCache will use a reader that
%   is associated with the file extension. No match throws an error. User
%   can add (or overwrite) his own file readers to extend the class
%   functionality.
%
%   Class instance is preserved in the persistant workspace and is
%   unavailable to user directly. If the class instance is not present, it
%   will be created upon calling any of the class methods. 'clear all' wipes 
%   the cache so in your scripts use 'clear' instead.
%
%   This class cannot be instantiated (all public methods static), therefore all
%   calls to the member functions must be precedeed with classname, like: DataCache.MethodName()
%
% AVAILABLE METHODS:
%
%   SetDir - sets current search path
%   GetDir - gets current serach path
%   Load - load file from disk or cache
%   List - lists files retained in cache
%   Clean - wiped the data in the cache
%   AddReader - add a custom reader for file loading
%   ListReaders - lists available readers
%   ResetReaders - restoers readers to the default state
%   SetCacheSizeLimitMb - sets the cap on memory available to cache
%   GetCacheSizeLimitMb - gets the current memory cap
%   ResetCacheSizeLimit - removes the memory cap
%   GetCachedDataSizeMb - gets the size of data stored in cache
%   VerboseEnable - enables verbose messages (default)
%   VerboseDisable - disable verbose messages
%
% EXAMPLES:
%
%   A simple usage example
%
%   % sets the default search path
%   DataCache.SetDir('C:\testdata\');
%   % Loads a TDMS file from 'C:\testdata\'
%   data1 = DataCache.Load('data1.tdms');
%   % Load a mat file from current dir (the search path remains 'C:\testdata\')
%   data2 = DataCache.Load('data2.mat','.');
% 
%   Using a custom reader and memory cap. Disabling messages.
%   % set memory cap to 1GB
%   DataCache.SetCacheSizeLimitMb(1024);
%   % create my custom reading function for .xls. Any function handle will do:
%   % anonymous, local or m-script
%   read_func = @(filename)readtable(filename, 'Delimiter',' ','ReadVariableNames',false)
%   DataCache.AddReader('.xls', read_func);
%   % load my .xls file
%   DataCache.Load('spreadsheet_data.xls','.');
%
% See also:
%   DATACACHE/SetDir
%   DATACACHE/GetDir
%   DATACACHE/Load
%   DATACACHE/List
%   DATACACHE/Clean
%   DATACACHE/AddReader
%   DATACACHE/ListReaders 
%   DATACACHE/ResetReaders
%   DATACACHE/SetCacheSizeLimitMb
%   DATACACHE/GetCacheSizeLimitMb
%   DATACACHE/ResetCacheSizeLimit
%   DATACACHE/GetCachedDataSizeMb
%   DATACACHE/VerboseEnable  
%   DATACACHE/VerboseDisable 
%
%   Author: Jeremi Wójcicki, jeremi.wojcicki(at)gmail.com
%   License: GNU Lesser General Public License v3.0

classdef DataCache < handle
    properties (Access = private)
        cache       % storage for cached data
        dir         % current dir
        verbose     % verbose enable/disable flag
        reader_list % list of file extensions and associated readers
        mem_cap_mb  % cache memory limit
    end
    
%% private static helper methods
    
    methods (Static = true, Access = private)

        % returns the singleton instance of the class
        function obj = getInstance()
            persistent local
            if isempty(local)
                local = DataCache();
            end
            obj = local;
        end
        
        % natively supported file readers
        
        % simple ascii files
        function output = asciiReader(path)
            f = fopen(path,'r');
            output = fread(f,'*char')';
            fclose(f);
        end
       
        % matlab data
        function output = matlabReader(path)
            output = load(path);
        end
        
        % TDMS by for LabView files
        function output = tdmsReader(path)
            if(exist('TDMS_readTDMSFile','file'))
                output = TDMS_readTDMSFile(path);
            else
                error('TDMS reader library is not present (TDMS_readTDMSFile has not been found). You can download it from: https://www.mathworks.com/matlabcentral/fileexchange/30023-tdms-reader')
            end
        end
        
        % returns absolute path
        function path = absPath(path)
            if(~isfolder(path))
                error('Not a dir')
            end
            
            if ~java.io.File(path).isAbsolute
                path = fullfile(pwd,path);
                path = char(java.io.File(path).getCanonicalFile());
            end
        end
        
    end
 
 %% public methods - all static
    
    methods (Static = true)
               
        function AddReader(extensions, func_handle)
        % AddReader adds user-defined reader to the list  
        %
        %   AddReader(extensions, func_handle) sets a function handle
        %   used for reading files with given extensions. Extension
        %   can be a char e.g. '.txt' or cell array of chars
        %   {'.txt','.cvs'}. If a given extension alread has a reader,
        %   it will be overwritten. To restore reader list to original
        %   state use ResetReaders
        % 
        %   See also DATACACHE/RESETREADERS, DATACACHE/LISTREADERS, DATACACHE 
            obj = DataCache.getInstance();
            obj.AddReaderPriv(extensions, func_handle);
        end
        
        % restores reades to its default setting
        function ResetReaders()
        % 
        %   See also DATACACHE/ADDREADER, DATACACHE/LISTREADERS, DATACACHE 
            obj = DataCache.getInstance();
            obj.reader_list(:) = [];
            obj.defaultReaderSet();
        end
        
        function varargout = ListReaders()
        % ListReaders displays a lists of the handled file extensions
        % and the associated file readers 
        % 
        %   See also DATACACHE/ADDREADER, DATACACHE/RESETREADERS, DATACACHE 
            obj = DataCache.getInstance();
            if(nargout == 1)
                varargout{1} = obj.reader_list;
            elseif(nargout == 0)
                if(~isempty(obj.reader_list))
                    for r = obj.reader_list
                        obj.Info(['.' r.ext ' => ' char(r.func)])
                    end
                else
                    obj.Info('No readers available. Use DataCache.AddReader to add supported filetypes');
                end
            else
                error('Too many output arguments, expected 0 or 1');
            end
        end
        
        function SetCacheSizeLimitMb(limit)
        % SetCacheSizeLimitMb sets the size limit for the cache RAM storage
        %
        %   SetCacheSizeLimitMb(limit) set the limit in MB. When user loads
        %   more data than the cap, the oldest accessed files will be
        %   purged from the cache until enough space is freed to accomodate
        %   the new data.
        %
        %   See also DATACACHE/ResetCacheSizeLimit, DATACACHE/GetCacheSizeLimitMb,
        %   DATACACHE/GetCachedDataSizeMb, DATACACHE
            obj = DataCache.getInstance();
            % purge the cache if current size exceeds the limit
            if(limit < 100)
                limit = 100;
                warning('Chosen cache limit is too small. Using default minimum cache size (100MB).')
            else
                obj.Verbose(['Cache limit set to ' num2str(limit,'%.2f') 'MB']);
            end
            
            obj.mem_cap_mb = limit;
            
            % free some files from the cache if they no longer fit
            obj.FreeCacheForNewData(0);
            
            obj.MemUsage();
        end
        
        function ResetCacheSizeLimit()
        % ResetCacheSizeLimit removes the cache size cap
        %
        %   The maximum cache size will be limited only by the RAM 
        %   available to MATLAB. If user attempts to load more data than 
        %   available space an error will be thrown.
        %
        %   See also DATACACHE/SetCacheSizeLimitMb,
        %   DATACACHE/GetCacheSizeLimitMb, DATACACHE/GetCachedDataSizeMb, 
        %   DATACACHE
            obj = DataCache.getInstance();
            obj.mem_cap_mb = -1;
            obj.Verbose('Cache size limit removed. Cache size will be limited by the memory available to MATLAB.');
        end
        
        % returns current cache cap in MB
        function limit = GetCacheSizeLimitMb()
        % GetCacheSizeLimitMb returns the current memory cap on cache in MB
        %
        %   If there is no limit set the function returns -1. If no output
        %   paramter is specified, information is displayed in the console
        %
        %   See also DATACACHE/SetCacheSizeLimitMb,
        %   DATACACHE/ResetCacheSizeLimit, DATACACHE/GetCachedDataSizeMb,
        %   DATACACHE
            obj = DataCache.getInstance();
            if nargout > 0
                limit = obj.mem_cap_mb;
            else
                if(obj.mem_cap_mb > 0)
                    obj.Info(['Cache size limit: ' num2str(obj.mem_cap_mb) 'MB']);
                else
                    obj.Info('No cache size limit set. Cache size will be limited by the memory available to MATLAB.')
                end
            end
        end
        
        function mb = GetCachedDataSizeMb()
        % GetCachedDataSizeMb returns the size of data in cache in MB
        %
        %   See also DATACACHE/SetCacheSizeLimitMb,
        %   DATACACHE/ResetCacheSizeLimit, DATACACHE/GetCacheSizeLimitMb,
        %   DATACACHE/GetCachedDataSizeMb, DATACACHE
            obj = DataCache.getInstance();
            cache = obj.cache; %#ok<NASGU>
            info = whos('cache');
            mb = info.bytes/(1024^2);
        end
          
        function SetDir(dir)
        % SetDir sets the search path
        %
        %   SetDir(dir) sets the path where the class will look for when
        %   loading files (unless dir is explcitly provided to the
        %   DataCache.Load). 'dir' can be either an absolute or a relative
        %   path. The default dir is the working directory at the moment of
        %   class instantaniation.
        %
        %   See also DATACACHE/GetDir, DATACACHE/Load, DATACACHE
            validateattributes(dir,{'char','string'},{'vector'})
            try
                obj = DataCache.getInstance();
                obj.dir = DataCache.absPath(dir);
                obj.Verbose(['Current directory: ' obj.dir]);
            catch
                error('User provided input does not consititute a valid directory path.')
            end
        end
        

        function dir = GetDir()
        % GetDir gets the current search path
        %
        %   If no output paramter is specified, information is displayed 
        %   in the console.
        %
        %   See also DATACACHE/GetDir, DATACACHE/Load, DATACACHE
            obj = DataCache.getInstance();
            if nargout > 0
                dir = obj.dir;
            else
                obj.Info(['Current directory: ' obj.dir]);
            end
        end

        function data = Load(varargin)
        % Load retrieves the content of the file processed via
        % reader funtion (associated to the file extension). The file first
        % attempts to find a matching item in the cache, comparing full
        % path and file timestamp. If match is found, the cache contents
        % are given to the user (quick data access). In case of cache miss
        % data is loaded from the disk (slow data access).
        % 
        % Usage:        
        %
        %   data = Load() opens a file loading dialog. It will allow only
        %   to load files for which there are file readers available. Upon
        %   loading the currect DataCache directory will be modified to the
        %   one from which the last file was selected.
        %
        %   data = Load(file) loads the file from the directory
        %   specified by user using DataCache.SetDir. 'file' input paramter
        %   is expected to be a filename or a relative path. The absolute
        %   path throws an error.
        %
        %   data = Load(file, directory) loads the file contents using
        %   explicitly provided directory. The 'directory' parameter may be an
        %   absolute or relative to current matlab working directory.
        %   The default search path is not modified by this method call.
        %
        %   See also DATACACHE/SetDir, DATACACHE/GetDir, DATACACHE
              
            obj = DataCache.getInstance();
            
            if(nargin == 0)
                
                readers = DataCache.ListReaders();
                ext = {readers(:).ext};
                ext = strcat('*.',ext);
                
                ext_coma = strjoin(ext,', ');
                ext_semi = strjoin(ext,';');
                
                [file, directory] = uigetfile({ext_semi,['Available readers (' ext_coma ')']}, 'Choose a file to read via DataCache', obj.dir);
                if(file == 0)
                    obj.Verbose('User did not select a file. No data was loaded.');
                    return;
                end
                % we will override directory by user default
                DataCache.SetDir(directory);
            elseif (nargin == 1)
                file = varargin{1};
                directory = obj.dir;
            elseif(nargin == 2)
                file = varargin{1};
                directory = DataCache.absPath(varargin{2});
            end
            
            path = fullfile(directory,file);
            
            obj.Verbose(['Elaborating ' path ' ...' ])
            
            % find loader base on the extension
            [~,~,ext] = fileparts(path);
            if(ext(1) == '.')
                ext(1) = [];
            end
            func = obj.FindLoader(ext);
            if(isempty(func))
                error(['File type "' ext '" is not supported. You need to provide a user-defined reader function handle.'])
            else
                
                % check if file already exists in cache
                
                try
                    % look for file name match. If this throw an error we
                    % have a cache miss.
                    idx = find(contains({obj.cache(:).path},path),1);
                    data = obj.cache(idx).data;
                    file_info = dir(path);
                    
                    % comepare file timestamps
                    if(strcmp(obj.cache(idx).timestamp, file_info.date))
                        obj.cache(idx).last_access = datetime();
                        obj.Verbose('Cache hit! Data loaded from memory.')
                    else
                        obj.Verbose(['Timestamp mismatch: ' obj.cache(idx).timestamp ' vs. ' file_info.date])
                        error('cache miss')
                    end
                catch
                    
                    obj.Verbose('Cache miss! Loading data from disk ...');
                    % load data and put in cache
                    try
                        obj.Verbose(['Using ' char(func) ' file reader.']);
                        
                        % loading from file
                        data = func(path);
                        
                        % check the size of new data
                        info = whos('data');
                        data_size_mb = info.bytes/(1024^2);
                        obj.Verbose(['Read data size: ' num2str(data_size_mb,'%.2f') 'MB']);
                        
                        % if size limit is enabled check if the data will fit in the cache
                        % and start purging it to make enough space for the
                        % new data
                        if(obj.mem_cap_mb > 0)
                            % check if data will fit in the cache (entire)
                            if(data_size_mb > obj.mem_cap_mb)
                                error 'Not enough space to load the data. Increase the cache size.'
                            else
                                obj.FreeCacheForNewData(data_size_mb);
                            end
                        end
                        % idx pointing to the nearest free slot
                        idx = length(obj.cache)+1;
                        
                        obj.cache(idx).data = data;
                        obj.cache(idx).path = path;
                        obj.cache(idx).last_access = datetime();
                        file_info = dir(path);
                        obj.cache(idx).timestamp = file_info.date;
                        obj.Verbose('Data successfully loaded cache.');
                        obj.MemUsage();
                    catch e
                        error(['File reader returned an error: ' e.message])
                    end
                end
            end
        end
        
        function List()
        % List displays a list of cached files
        %
        %   See also DATACACHE/Clean, DATACACHE
            obj = DataCache.getInstance();
            if(numel(obj.cache) > 0)
                disp(['Cached files: ' num2str(numel(obj.cache)) '.']);
                for item = obj.cache
                    disp(item.path)
                end
            else
                disp('Cache is empty.');
            end
        end
        
        function Clean()
        % Clean wipes the cache contents
        %
        %   See also DATACACHE/List, DATACACHE
            obj = DataCache.getInstance();
            cache = obj.cache; %#ok<NASGU>
            info = whos('cache');
            clear cache
            obj.cache = [];
            if(obj.verbose)
                if(~isempty(info))
                    disp(['Cache deleted. Released ' num2str(info.bytes/1024^2,'%.2f') 'MB of memory'])
                else
                    disp('Nothing to free. Cache is already empty.')
                end
            end
        end

        function VerboseEnable(yes_or_no)
        % VerboseEnable enables or disables textual messages from DataCache
        %
        % Usage:
        %
        %   VerboseEnable() enables messages
        %
        %   VerboseEnable(yes_or_no) enables or disables messages depending on
        %   the value of the 'yes_or_no' boolean flag. Integer values are
        %   also accepted.
        %
        %   See also DATACACHE/VerboseDisable, DATACACHE    
            obj = DataCache.getInstance();
            
            if(nargin > 0)
                validateattributes(yes_or_no,{'logical','numeric'},{'scalar'})
            else
                yes_or_no = true;
            end       
            
            if(yes_or_no)
                obj.verbose = yes_or_no;
                obj.Verbose('Displaying verbose messages enabled.')
            else
                obj.Verbose('Displaying verbose messages disabled.')
                obj.verbose = yes_or_no;
            end
                       
        end
        
        function VerboseDisable()
        % VerboseDisable disables textual messages from DataCache and functionally
        % is equal to 'DataCache.VerboseEnable(false)'
        %
        %   See also DATACACHE/VerboseEnable, DATACACHE    
            DataCache.VerboseEnable(0);
        end
        
    end
 
 %% internal methods
    
    methods (Access = private)
        
        % private constructor, so user would not be able create his own
        % instances
        function obj = DataCache()
            obj.verbose = true;
            obj.Verbose('Initializing a new DataCache instance ...');
            
            obj.cache = [];
            obj.mem_cap_mb = -1;
            
            obj.dir = DataCache.absPath('.');
            obj.defaultReaderSet();
            
            obj.Verbose('... done.');
        end
        
        % loads the default reader set into the reader list
        function defaultReaderSet(obj)
            
            obj.reader_list = struct('ext',{},'func',{});
            
            obj.AddReaderPriv({'txt','dat'}, @DataCache.asciiReader)
            obj.AddReaderPriv('mat', @DataCache.matlabReader)
            obj.AddReaderPriv('tdms', @DataCache.tdmsReader)
            
        end
        
        % adds a file reader to the list with associated extensions
        function AddReaderPriv(obj, extensions, func_handle)
            for ext = string(extensions)
                extc = char(ext);
                if(extc(1) == '.')
                    extc(1) = [];
                end
                [~,idx] = obj.FindLoader(extc);
                if(idx > 0)
                    f = obj.reader_list(idx).func;
                    obj.reader_list(idx) = struct('ext', extc, 'func', func_handle);
                    obj.Verbose(['Overwriting existing ".' extc '" file type reader "' char(f) '" with "' char(func_handle) '".'])
                else
                    obj.reader_list(end+1) = struct('ext', extc, 'func', func_handle);
                    obj.Verbose(['Added ".' extc '" file type reader "' char(func_handle) '".'])
                end
            end
        end
        
        function [func, idx] = FindLoader(obj, ext)
            func = [];
            for idx = length(obj.reader_list):-1:1
                if(strcmpi(obj.reader_list(idx).ext, ext))
                    func = obj.reader_list(idx).func;
                    return
                end
            end
            idx = 0;
        end
        
        % prints out message if in the verbose mode
        function Verbose(obj, msg)
            if(obj.verbose)
                disp(['DataCache(V): ' msg]);
            end
        end
        
        % prints out message
        function Info(~, msg)
            disp(['DataCache(I): ' msg]);
        end
        
        % erases items from the cache looking for the oldest (by access) to
        % fit in the new data
        function FreeCacheForNewData(obj, data_size_mb)
            msg = true;
                       
            while(data_size_mb + DataCache.GetCachedDataSizeMb() > obj.mem_cap_mb)
                if(msg)
                    obj.Verbose('Non enough space in the cache. Removing oldest accessed items.');
                    msg = false;
                end
                if(~isempty(obj.cache))
                    [~,i] = min([obj.cache(:).last_access]);
                    data = obj.cache(i).data; %#ok<NASGU>
                    info = whos('data');
                    obj.Verbose(['Freeing ' num2str(info.bytes/1024^2,'%.2f') 'MB => ' obj.cache(i).path]);
                    obj.cache(i) = [];
                end
                
            end
        end
        
        % displays and returns percentage use of the memory: either of the
        % cache, if there is cache cap or to the MATLAB, if no cap was
        % provided
        function usage = MemUsage(obj)
            usage_func = @(used,total) used/total*100;
            if(obj.mem_cap_mb > 0)
                used = DataCache.GetCachedDataSizeMb();
                total = DataCache.GetCacheSizeLimitMb();
            else
                m = memory();
                used = DataCache.GetCachedDataSizeMb();
                total = (m.MemAvailableAllArrays + m.MemUsedMATLAB)/1024^2;
            end
            usage = usage_func( used, total );
            if(nargout == 0)        
                obj.Verbose(['Cache at ', num2str(used,'%.2f')  ' MB out of total ' num2str(total,'%.2f') 'MB of memory available (used ' num2str(usage,'%.1f') '%).']);
            end
            
        end
    end
end
