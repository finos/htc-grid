package com.htcgrid.examples;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

// Handler value: example.Handler
public class MockComputeEngine implements RequestHandler<Map<String,Object>, Map<String, String> >{

  public static int invocation_count = 0; // Static variables preserved between invocation

  @Override
  public HashMap<String, String> handleRequest(Map<String,Object> event, Context context)
  {
    long start_time_ms = System.currentTimeMillis();
    HashMap<String, String> worker_response = new HashMap<>();


    // <1.> Print input event
    System.out.println("HTC-Grid Lambda invocation");
    for (Map.Entry<String, Object> e : event.entrySet()) {
      System.out.println(e.getKey() + ":" + e.getValue().toString());
    }


    // <2.> Extract value of the worker_arguments
    List<String> worker_args = new ArrayList<String>();
    worker_args = (List<String>) event.get("worker_arguments");
    int sleep_time_ms = Integer.parseInt(worker_args.get(0));


    // <3.> Do useful computation
    try {

      Thread.sleep(sleep_time_ms);
      System.out.println("Invocation count: " + Integer.toString((invocation_count)));
      invocation_count = invocation_count + 1;
      worker_response.put("result", "Success");

    } catch (InterruptedException e1) {

      worker_response.put("result", "Failure");
      e1.printStackTrace();
    }

    // <4.> Bookkeeping and construct response
    worker_response.put("compute_time_ms", Long.toString(System.currentTimeMillis()-start_time_ms));
    worker_response.put("check", Integer.toString(sleep_time_ms));

    return worker_response;
  }
}