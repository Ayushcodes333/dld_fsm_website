#include <bits/stdc++.h>

using namespace std;

vector<int> calculateParity(vector<int> states){
    int p1 = states[0] ^ states[1] ^ states[3];
    int p2 = states[0] ^ states[2] ^ states[3];
    int p4 = states[1] ^ states[2] ^ states[3];
    int p0 = p1 ^ p2 ^ p4 ^ states[0] ^ states[1] ^ states[2] ^ states[3];
    return {p0, p4, p2, p1};
}

bool secdedChecker(vector<int>& states, vector<int> parity, bool& doubleError){
    int p1 = states[0] ^ states[1] ^ states[3];
    int p2 = states[0] ^ states[2] ^ states[3];
    int p4 = states[1] ^ states[2] ^ states[3];

    int s1 = p1 ^ parity[3];
    int s2 = p2 ^ parity[2];
    int s3 = p4 ^ parity[1];
    int syn = (s3 << 2) | (s2 << 1) | s1;

    int overall = parity[0] ^ parity[1] ^ parity[2] ^ parity[3] ^
                  states[0] ^ states[1] ^ states[2] ^ states[3];

    if(syn == 0 && overall == 0) return true; //no error

    if(overall == 1){ //single bit error
        if(syn == 3) states[0] ^= 1;
        else if(syn == 5) states[1] ^= 1;
        else if(syn == 6) states[2] ^= 1;
        else if(syn == 7) states[3] ^= 1;
        return true; //corrected
    }

    doubleError = true; //double bit error
    return false;
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
    vector<int> states{0, 0, 0, 0};
    vector<int> parity{0, 0, 0, 0};

    //
    int code0, code1, code2, code3;
    code0 = 1; code1 = 0; code2 = 1; code3 = 1;
    bool isLocked = false;
    bool doubleError = false;

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

        parity = calculateParity(states);
        secdedChecker(states, parity, doubleError);
    }

    if(stateChecker(states) && !isLocked && !doubleError) cout<<"AUTHENTICATED"<<endl;
    else cout<<"NOT AUTHENTICATED"<<endl;
}
