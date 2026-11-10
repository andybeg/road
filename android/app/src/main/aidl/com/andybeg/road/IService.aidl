package com.andybeg.road;

import com.andybeg.road.IServiceCallback;

interface IService {
  int getStatus();
  void registerCallback(in IServiceCallback callback);
  oneway void unregisterCallback(in IServiceCallback callback);
}