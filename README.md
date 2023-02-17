## GAEN Analyzer

This app allows public health agencies that are using GAEN, the Google/Apple exposure notification system, to download, analyze and export the analytics made available from the ENPA and ENCV servers. In order to use this app, you must have created apiKeys for your organization through the ENPA and ENCV portals. It will work if you only have an apiKey for one or both of the two servers. You will need to copy and paste the api keys into the app, they are way too long to type in. 

To gain access to the iOS version of the app, contact [Professor Bill Pugh](bill.pugh@gmail.com). The iOS version also runs on iPads. The iOS version requires iOS  15, the macOS version requires macOS 12. The macOS version can be downloaded from the releases section on GitHub. 

All analyzed/presented data is rolling averages, over periods such as 7 days or 14 days. The ENPA metrics include noise due to differential privacy. 

All ENPA and ENCV data is kept private to the app except as exported by the user as csv files. 

Because the APHL servers for ENCV data only retain data for 90 days, the GAEN analyzer locally persists ENCV data, so that old ENCV data is not lost. If you have composite-stats.csv files you have previously downloaded, you can load those files into the app. When new ENCV data is downloaded, it is updates the data for the newly downloaded dates, keeping the data for dates not in the download. 

The GAEN Analyzer is under active development to help public health authorities access, interprete and understand their ENPA and ENCV analytics. It  is open source, available at https://github.com/billpugh/GAEN-Analytics, under the MIT license. So far, all of the code has been written by Professor Bill Pugh, University of Maryland. 
