#include <bits/stdc++.h>

using namespace std;

bool dmrChecker(vector<int> s1, vector<int> s2){
    for(int i = 0; i < 4; i++){
        if(s1[i] != s2[i]) return false;
    }
    return true;
}

bool stateChecker(vector<int> states){
    bool isPass = true;
    int val0, val1, val2, val3;
    val0 = 1; val1 = 0; val2 = 1; val3 = 0; //setStates;

    if(states[0] != val0) isPass = false;
    if(states[1] != val1) isPass = false;
    if(states[2] != val2) isPass = false;
    if(states[3] != val3) isPass = false;

    return isPass;
}

int main(){
    int n = 4;
    vector<int> states1{0, 0, 0, 0};
    vector<int> states2{0, 0, 0, 0};

    //
    int code0, code1, code2, code3;
    code0 = 1; code1 = 0; code2 = 1; code3 = 1;
    bool isLocked = false;
    bool mismatch = false;

    for(int i = 0; i < n; i++){
        int temp; cin>>temp;

        //Core 1
        if(i == 0){
            if(temp == code0 && isLocked == false) states1[i] = 1;
            else{
                isLocked = true;
                states1 = {0, 0, 1, 1};
            }
        }
        else if(i == 1){
            if(temp == code1 && isLocked == false) states1[i] = 0;
            else{
                isLocked = true;
                states1 = {0, 0, 1, 1};
            }
        }
        else if(i == 2){
            if(temp == code2 && isLocked == false) states1[i] = 1;
            else{
                isLocked = true;
                states1 = {0, 0, 1, 1};
            }
        }
        else if(i == 3){
            if(temp == code3 && isLocked == false) states1[i] = 0;
            else{
                isLocked = true;
                states1 = {0, 0, 1, 1};
            }
        }

        //Core 2
        states2 = states1;

        if(!dmrChecker(states1, states2)) mismatch = true;
    }

    if(stateChecker(states1) && stateChecker(states2) && !mismatch && !isLocked) cout<<"AUTHENTICATED"<<endl;
    else cout<<"NOT AUTHENTICATED"<<endl;
}
