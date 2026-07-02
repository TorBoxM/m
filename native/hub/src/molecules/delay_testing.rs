// 延迟测试分子模块

pub mod tester;

pub use tester::{
    BatchDelayTestComplete, BatchDelayTestRequest, CancelDelayTestsRequest, DelayTestProgress,
    SingleDelayTestRequest, SingleDelayTestResult,
};

pub fn init_listeners() {
    tester::init();
}
