#include <bits/stdc++.h>

using namespace std;

vector<int> tmrVoter(vector<int> a, vector<int> b, vector<int> c){
    vector<int> voted(4);
    for(int i = 0; i < 4; i++){
        voted[i] = (a[i] & b[i]) | (b[i] & c[i]) | (a[i] & c[i]);
    }
    return voted;
}

bool consensusAuth(bool a, bool b, bool c){
    return (a && b) || (b && c) || (a && c);
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
    vector<int> states3{0, 0, 0, 0};

    //
    int code0, code1, code2, code3;
    code0 = 1; code1 = 0; code2 = 1; code3 = 1;
    bool isLocked = false;

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

        //Core 2 and Core 3
        states2 = states1;
        states3 = states1;
    }

    vector<int> votedStates = tmrVoter(states1, states2, states3);

    bool auth1 = stateChecker(states1);
    bool auth2 = stateChecker(states2);
    bool auth3 = stateChecker(states3);

    if(consensusAuth(auth1, auth2, auth3) && !isLocked) cout<<"AUTHENTICATED"<<endl;
    else cout<<"NOT AUTHENTICATED"<<endl;
}
