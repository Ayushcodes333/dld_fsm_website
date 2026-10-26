#include <bits/stdc++.h>

using namespace std;

bool weightChecker(vector<int> states){
    int oneCount = 0;
    for(int i = 0; i < 5; i++){
        if(states[i] == 1) oneCount++;
    }

    if(oneCount%2 == 0) return true;
    return false;
}

bool stateChecker(vector<int> states){
    bool isPass = true;
    int val0, val1, val2, val3, val4;
    val0 = 0; val1 = 1; val2 = 0; val3 = 0; val4 = 1; //setStates (SUCCESS = 01001);
    
    if(states[0] != val0) isPass = false;
    if(states[1] != val1) isPass = false;
    if(states[2] != val2) isPass = false;
    if(states[3] != val3) isPass = false;
    if(states[4] != val4) isPass = false;
    
    return isPass;
}

int main(){
    int n = 4;
    vector<int> states{0, 0, 0, 0, 0};

    //
    int code0, code1, code2, code3;
    code0 = 1; code1 = 0; code2 = 1; code3 = 0;
    bool isLocked = false;
    bool isTrapped = false;

    for(int i = 0; i < n; i++){
        int temp; cin>>temp;
        if(i == 0){
            if(temp == code0 && isLocked == false) states = {0, 0, 0, 1, 1}; //GOT_1
            else{
                isLocked = true;
                states = {0, 1, 0, 1, 0}; //ERR_1
            }
        }
        else if(i == 1){
            if(temp == code1 && isLocked == false) states = {0, 0, 1, 0, 1}; //GOT_10
            else{
                isLocked = true;
                states = {0, 1, 1, 0, 0}; //ERR_2
            }
        }
        else if(i == 2){
            if(temp == code2 && isLocked == false) states = {0, 0, 1, 1, 0}; //GOT_101
            else{
                isLocked = true;
                states = {1, 0, 0, 0, 1}; //ERR_3
            }
        }
        else if(i == 3){
            if(temp == code3 && isLocked == false) states = {0, 1, 0, 0, 1}; //SUCCESS
            else{
                isLocked = true;
                states = {1, 0, 0, 1, 0}; //LOCKED
            }
        }

        //check in-between trap
        if(!weightChecker(states)){
            isTrapped = true;
            states = {1, 1, 1, 1, 0}; //TRAP_LOCKED
        }
    }

    if(stateChecker(states) && !isLocked && !isTrapped) cout<<"AUTHENTICATED"<<endl;
    else cout<<"NOT AUTHENTICATED"<<endl;
}
