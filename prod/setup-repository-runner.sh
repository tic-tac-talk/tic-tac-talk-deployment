#!/bin/bash
set -e
echo "=== GitHub Actions Self-hosted Runner 설치 (Repository 방식) ==="
echo ""
# PAT 입력
read -sp "GitHub Personal Access Token 입력: " GITHUB_TOKEN
echo
echo ""
# 1. 기존 Runner 정리
echo "1. 기존 Runner 정리 중..."
kubectl delete runnerdeployment ttt-runner -n actions-runner-system 2>/dev/null || echo "  기존 Runner 없음"
sleep 5
# 2. Secret 업데이트
echo "2. Secret 업데이트 중..."
kubectl delete secret controller-manager -n actions-runner-system 2>/dev/null || true
kubectl create secret generic controller-manager \
  -n actions-runner-system \
  --from-literal=github_token="$GITHUB_TOKEN"
echo "  Secret 생성 완료"
# 3. Controller 재시작
echo "3. Controller 재시작 중..."
kubectl rollout restart deployment actions-runner-controller -n actions-runner-system
kubectl rollout status deployment actions-runner-controller -n actions-runner-system --timeout=300s
echo "  Controller 준비 완료"
sleep 20
# 4. Kubeconfig Secret 확인/생성
echo "4. Kubeconfig Secret 확인 중..."
if ! kubectl get secret runner-kubeconfig -n actions-runner-system &>/dev/null; then
    echo "  Kubeconfig Secret 생성 중..."
    kubectl create secret generic runner-kubeconfig \
      -n actions-runner-system \
      --from-file=config=$HOME/.kube/config
    echo "  Kubeconfig Secret 생성 완료"
else
    echo "  Kubeconfig Secret 이미 존재함"
fi
# 5. Runner Deployment 생성
echo "5. Runner Deployment 생성 중..."
cat <<'INNEREOF' | kubectl apply -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: ttt-runner
  namespace: actions-runner-system
spec:
  replicas: 2
  template:
    spec:
      repository: tic-tac-talk/tic-tac-talk-backend
      labels:
        - self-hosted
        - k8s
        - linux
      volumeMounts:
      - name: docker-sock
        mountPath: /var/run/docker.sock
      - name: kube-config
        mountPath: /root/.kube
        readOnly: true
      volumes:
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
          type: Socket
      - name: kube-config
        secret:
          secretName: runner-kubeconfig
      resources:
        limits:
          cpu: "2000m"
          memory: "4Gi"
        requests:
          cpu: "500m"
          memory: "1Gi"
INNEREOF
echo "  Runner Deployment 생성 완료"
# 6. Runner 시작 대기
echo "6. Runner 시작 대기 중... (30초)"
sleep 30
# 7. 상태 확인
echo ""
echo "========================================"
echo "         설치 완료!"
echo "========================================"
echo ""
echo "RunnerDeployment:"
kubectl get runnerdeployment -n actions-runner-system
echo ""
echo "Runners:"
kubectl get runners -n actions-runner-system
echo ""
echo "Pods:"
kubectl get pods -n actions-runner-system
echo ""
echo "Controller 로그 (최근 20줄):"
kubectl logs -n actions-runner-system deployment/actions-runner-controller --tail=20 | grep -i "error\|runner\|401" || echo "  에러 없음"
echo ""
echo "========================================"
echo "GitHub에서 확인:"
echo "https://github.com/tic-tac-talk/tic-tac-talk-backend/settings/actions/runners"
echo "========================================"
