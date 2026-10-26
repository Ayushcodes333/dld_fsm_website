#include <bits/stdc++.h>

using namespace std;

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
    vector<int> states{0, 0, 0, 0};

    //
    int code0, code1, code2, code3;
    code0 = 1; code1 = 0; code2 = 1; code3 = 1;
    bool isLocked = false;

    for(int i = 0; i < n; i++){
        int temp; cin>>temp;
        if(i == 0){
            if(temp == code0 && isLocked == false) states[i] = 1;
            else{
                isLocked = true;
                states = {0, 0, 1, 1};
            }
        }
        else if(i == 1){
            if(temp == code1 && isLocked == false) states[i] = 0;
            else{
                isLocked = true;
                states = {0, 0, 1, 1};
            }
        }
        else if(i == 2){
            if(temp == code2 && isLocked == false) states[i] = 1;
            else{
                isLocked = true;
                states = {0, 0, 1, 1};
            }
        }
        else if(i == 3){
            if(temp == code3 && isLocked == false) states[i] = 0;
            else{
                isLocked = true;
                states = {0, 0, 1, 1};
            }
        }
    }

    if(stateChecker(states) && !isLocked) cout<<"AUTHENTICATED"<<endl;
    else cout<<"NOT AUTHENTICATED"<<endl;
}
