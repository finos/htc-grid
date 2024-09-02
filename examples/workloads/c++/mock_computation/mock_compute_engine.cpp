/**
* Copyright 2024 Amazon.com, Inc. or its affiliates. 
* SPDX-License-Identifier: Apache-2.0
* Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/
**/

#include <iostream>
#include <vector>
#include <cstdlib>
#include <unistd.h>
#include <string>

using namespace std;


int main(int argc, char *argv[]) {


    if (argc != 4) {
        cout << " Usage engine <forced_delay_ms> <ram_limit_GB> <iter_limit_millions>";
        cout << "Forced delay in milliseconds. If >= 0 then computations will be ignored";
        cout << " and system will sleep for the specified duration. Set to -1 to use computations";
        cout << "ram_limit_BG - approximate size of RAM to allocate";
        cout << "iter_limit_millions - number of iterations to compute, has linear affect on execution time";

        exit(1);
    }

    unsigned long long int forced_delay_ms = std::stoull (argv[1]);

    if (forced_delay_ms >= 0) {
        usleep(forced_delay_ms*1000);
        cout << forced_delay_ms << endl;
    } else {

        int ram_limit = atoi(argv[2]);
        int iter_limit = atoi(argv[3]);

        int int_size = sizeof(long);

        int vmaxsize = ram_limit * 1E9 / int_size ;

        vector<long> vec;

        // cout << int_size << endl;
        // cout << vmaxsize << endl;

        vec.push_back(long(0));
        vec.push_back(long(1));

        long index1, index2, value = 123;
        for (long i = 2; i < iter_limit * 1000 * 1000 ; i++) {

            index1 = (i - 2) % vmaxsize;
            index2 = (i - 1) % vmaxsize;
            value = (vec.at(index1) + vec.at(index2)) % 1000000000;
            // cout << i << " " << value << endl;
            if (i < vmaxsize) {
                vec.push_back(long(value));
            } else {
                // vec.push_back(long(value));
                vec.at(i % vmaxsize) = value;
            }
        }
        // cout << "Hello! " << ram_limit << " " << iter_limit << endl;
        cout << value << endl;
        // sleep(10000);
    }



    return 0;
}