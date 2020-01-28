# MATLAB-DataCache
Summary: A class that caches loaded disk files in RAM for faster reloads



The intention of this class is to speed up the scripts which rely on external data files, particularly that need some sort of conversion e.g. tdms or spreadsheets. Using DataCache class allows to cache the results of file loading in MATLAB's presistent memory, so sequential reads will result in data being retrieved from RAM rather than disk.

Use cases:
In m-scripts it common to load a file on every time you run the script, which has a bad performance pentaly. Often the workaround is loading the file conditionally, that is if the output variable exists it means the file has been loaded, so you use the contents of this file e.g.:

```matlab
if(~exists('data'))
data = load('somefile.mat')
end
```

However clearing workspace memory ('clear') erases the data variable, the data may also be overwritten or modified in another script leading to unpredictable behaviour. The DataCache overcomes this problem by keeping the data copies in the persistent memory that is not visible to the user. Data cache 'survives' the 'clear' command, but will be erased by 'clear all' command (whose use is discuraged unless used conciously). The example usage is as follows:

```matlab
% clear old script vars (but the cache remains intact)
clear
% sets the search path
DataCache.SetDir('C:\testdata\');
% retrieves data from file
data1 = DataCache.Load('data.tdms');
% retrieves data from cache (much faster)
data2 = DataCache.Load('data.tdms');
```

Running the script again, both DataCache.Load call will retrieve cache data, as the memory is persistent:

The large overhead can be cause also by the file parsing/conversions, and the DataCache hold only the final output data, not the raw file data, therefore speeding up the execution:

The first-time file loading flowchart:
USER REQUEST => [DISK FILE] => FILE READING => [RAW DATA] => CONVERSION/PARSING => [MATLAB VARIABLE] => PASSING TO USER & KEEPING COPY IN CACHE
Sequential reads to the same file:
USER REQUEST => [CACHE] => PASSING TO USER

DataCache supports predefined and custom user-defined readers (functions for loading data from chosen file format). It is possible to limit memory cache. Updates of the file contents will not be unnoticed, as file timestamps are also traced. For detailed description of the class look into DataCache help as well as the help for its member function i.e. 'help DataCache/Load'.
