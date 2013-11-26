T2StarMap
=========

Simple Matlab tool for calculating T2* maps from MRI data.

Usage:
To run the GUI, type T2StarMapGUI at the Matlab command line. 

A command line function also exists:

[map S0 rmse] = t2starmap(data,TE)
  Calculates T2* map from data
  Data is a either a 3D or 4D array, where the last dimension relates to
  the echo.
 
  S0 is the estimated magnitude at t=0.
  rmse is the root-mean-square error of the T2* map.
  
This package includes the "Tools for NIfTI and ANALYZE image" package by Jimmy Shen. For
more information about this package, see

http://research.baycrest.org/~jimmy/NIfTI/
  
--------------------------------------------------
Created by Amanda Ng 18 October 2013
Contact: amanda.ng@monash.edu